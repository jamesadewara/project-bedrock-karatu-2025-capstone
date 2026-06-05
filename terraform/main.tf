data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_string" "db_password" {
  length  = 16
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# VPC MODULE
module "vpc" {
  source = "./modules/vpc"

  name                 = var.vpc_name
  availability_zones   = var.availability_zones
  common_tags          = { Project = var.project_tag }
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# EKS MODULE
module "eks" {
  source = "./modules/eks"

  cluster_name            = var.cluster_name
  cluster_version         = var.eks_version
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  public_subnet_ids       = module.vpc.public_subnet_ids
  app_namespace           = var.app_namespace
  aws_region              = var.region
  eks_public_access_cidrs = var.eks_public_access_cidrs
  common_tags             = { Project = var.project_tag }
  dev_user_arn            = aws_iam_user.dev_view.arn
  db_username             = var.db_username
  db_password             = random_string.db_password.result
  db_name_catalog         = var.db_name_catalog
  db_name_orders          = var.db_name_orders
}

# RDS MODULE - Managed Data Layer
module "rds" {
  source = "./modules/rds"

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  eks_security_group_id = module.eks.node_security_group_id
  eks_cluster_name      = var.cluster_name
  db_username           = var.db_username
  db_password           = random_string.db_password.result
  db_name_catalog       = var.db_name_catalog
  db_name_orders        = var.db_name_orders
  common_tags           = { Project = var.project_tag }

  depends_on = [module.vpc, module.eks]
}

# DYNAMODB TABLE - Cart Service
resource "aws_dynamodb_table" "carts" {
  name         = "bedrock-carts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Project = var.project_tag }
}

# IAM Role for Carts Service (IRSA) to access DynamoDB
resource "aws_iam_role" "carts_dynamodb" {
  name = "bedrock-carts-dynamodb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${module.eks.oidc_provider_url}:sub" = "system:serviceaccount:${var.app_namespace}:carts"
          "${module.eks.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Project = var.project_tag }
}

resource "aws_iam_role_policy" "carts_dynamodb" {
  name = "bedrock-carts-dynamodb-policy"
  role = aws_iam_role.carts_dynamodb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = aws_dynamodb_table.carts.arn
    }]
  })
}

# Kubernetes ServiceAccount for Carts with IRSA annotation
resource "kubernetes_service_account" "carts" {
  metadata {
    name      = "carts"
    namespace = var.app_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.carts_dynamodb.arn
    }
  }

  depends_on = [module.eks.kubernetes_namespace]
}

# SECRETS MANAGER - Database Credentials
resource "aws_secretsmanager_secret" "catalog_db" {
  name                    = "bedrock/catalog-db-credentials"
  description             = "Catalog RDS credentials"
  recovery_window_in_days = var.aws_secretsmanager_secret_db_recovery_window_in_days
  tags                    = { Project = var.project_tag }
}

resource "aws_secretsmanager_secret_version" "catalog_db" {
  secret_id = aws_secretsmanager_secret.catalog_db.id
  secret_string = jsonencode({
    host     = module.rds.catalog_endpoint
    port     = 3306
    username = var.db_username
    password = random_string.db_password.result
    dbname   = var.db_name_catalog
    jdbc_url = "jdbc:mysql://${module.rds.catalog_endpoint}:3306/${var.db_name_catalog}"
  })
}

resource "aws_secretsmanager_secret" "orders_db" {
  name                    = "bedrock/orders-db-credentials"
  description             = "Orders RDS credentials"
  recovery_window_in_days = var.aws_secretsmanager_secret_db_recovery_window_in_days
  tags                    = { Project = var.project_tag }
}

resource "aws_secretsmanager_secret_version" "orders_db" {
  secret_id = aws_secretsmanager_secret.orders_db.id
  secret_string = jsonencode({
    host     = module.rds.orders_endpoint
    port     = 5432
    username = var.db_username
    password = random_string.db_password.result
    dbname   = var.db_name_orders
    jdbc_url = "jdbc:postgresql://${module.rds.orders_endpoint}:5432/${var.db_name_orders}"
  })
}

# Kubernetes Secrets - RDS Credentials for Pods
resource "kubernetes_secret" "catalog_db" {
  metadata {
    name      = "catalog-db-credentials"
    namespace = var.app_namespace
  }

  data = {
    host     = module.rds.catalog_endpoint
    username = var.db_username
    password = random_string.db_password.result
    dbname   = var.db_name_catalog
  }

  type = "Opaque"

  depends_on = [module.rds, module.eks.kubernetes_namespace]
}

# Kubernetes Secret - RabbitMQ Credentials
resource "kubernetes_secret" "rabbitmq" {
  metadata {
    name      = "rabbitmq-credentials"
    namespace = var.app_namespace
  }

  data = {
    username = "bedrock-mq"
    password = random_string.mq_password.result
  }

  type = "Opaque"

  depends_on = [module.eks.kubernetes_namespace]
}

# Random password for RabbitMQ (separate from DB password)
resource "random_string" "mq_password" {
  length  = 32
  special = true
}

resource "kubernetes_secret" "orders_db" {
  metadata {
    name      = "orders-db-credentials"
    namespace = var.app_namespace
  }

  data = {
    host     = module.rds.orders_endpoint
    username = var.db_username
    password = random_string.db_password.result
    dbname   = var.db_name_orders
    jdbc_url = "jdbc:postgresql://${module.rds.orders_endpoint}:5432/${var.db_name_orders}"
  }

  type = "Opaque"

  depends_on = [module.rds, module.eks.kubernetes_namespace]
}

# Kubernetes ExternalName Services for RDS Databases
resource "kubernetes_service" "catalog_db" {
  metadata {
    name      = "catalog-db"
    namespace = var.app_namespace
  }

  spec {
    type             = "ExternalName"
    external_name    = module.rds.catalog_endpoint
    session_affinity = "None"
    port {
      port        = 3306
      target_port = 3306
      protocol    = "TCP"
    }
  }

  depends_on = [module.rds, module.eks.kubernetes_namespace]
}

resource "kubernetes_service" "orders_db" {
  metadata {
    name      = "orders-db"
    namespace = var.app_namespace
  }

  spec {
    type             = "ExternalName"
    external_name    = module.rds.orders_endpoint
    session_affinity = "None"
    port {
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }
  }

  depends_on = [module.rds, module.eks.kubernetes_namespace]
}

# S3 BUCKET - Assets
resource "aws_s3_bucket" "assets" {
  bucket = var.s3_bucket_name
  tags   = { Project = var.project_tag }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# LAMBDA FUNCTION - Asset Processor
resource "aws_iam_role" "lambda_execution" {
  name = "bedrock-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = { Project = var.project_tag }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "bedrock-lambda-s3-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ]
      Resource = "${aws_s3_bucket.assets.arn}/*"
    }]
  })
}

# Package Lambda code
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/index.py"
  output_path = "${path.module}/../lambda/bedrock-asset-processor.zip"
}

resource "aws_lambda_function" "asset_processor" {
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_execution.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  tags = { Project = var.project_tag }
}

# Lambda Permission for S3 Invocation
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asset_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.assets.arn
}

# S3 Event Notification
resource "aws_s3_bucket_notification" "assets" {
  bucket = aws_s3_bucket.assets.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.asset_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}



# IAM USER - Developer Access (bedrock-dev-view)
resource "aws_iam_user" "dev_view" {
  name = var.iam_user_dev
  tags = { Project = var.project_tag }
}

resource "aws_iam_user_login_profile" "dev_user_profile" {
  user                    = aws_iam_user.dev_view.name
  password_reset_required = false # Keeps AWS from forcing a change on first login

  lifecycle {
    ignore_changes = [
      password_reset_required
    ]
  }
}

resource "aws_iam_access_key" "dev_view" {
  user = aws_iam_user.dev_view.name
}

resource "aws_iam_user_policy_attachment" "dev_readonly" {
  user       = aws_iam_user.dev_view.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_user_policy" "dev_s3_put" {
  name = "bedrock-dev-s3-put"
  user = aws_iam_user.dev_view.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.assets.arn}/*"
    }]
  })
}


resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 7
  tags              = { Project = var.project_tag }

  lifecycle {
    ignore_changes  = [name] # Ignore if already exists
    prevent_destroy = false
  }
}

resource "aws_acm_certificate" "cert" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.domain_name}",
    "*.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = { Project = var.project_tag }
}

# GitHub Actions OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = { Project = var.project_tag }
}
