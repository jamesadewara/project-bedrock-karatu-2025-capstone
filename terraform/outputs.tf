output "cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS Cluster Name"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS Region"
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "assets_bucket_name" {
  description = "S3 Assets Bucket Name"
  value       = aws_s3_bucket.assets.bucket
}

output "catalog_db_endpoint" {
  description = "Catalog RDS Endpoint"
  value       = module.rds.catalog_endpoint
  sensitive   = true
}

output "orders_db_endpoint" {
  description = "Orders RDS Endpoint"
  value       = module.rds.orders_endpoint
  sensitive   = true
}

output "dynamodb_table_name" {
  description = "DynamoDB Carts Table Name"
  value       = aws_dynamodb_table.carts.name
}

output "carts_dynamodb_role_arn" {
  description = "IAM Role ARN for Carts Service (IRSA)"
  value       = aws_iam_role.carts_dynamodb.arn
}

output "lambda_function_arn" {
  description = "Lambda Function ARN"
  value       = aws_lambda_function.asset_processor.arn
}

output "dev_user_access_key_id" {
  description = "Developer Access Key ID"
  value       = aws_iam_access_key.dev_view.id
  sensitive   = true
}

output "dev_user_secret_access_key" {
  description = "Developer Secret Access Key"
  value       = aws_iam_access_key.dev_view.secret
  sensitive   = true
}

output "dev_user_console_password" {
  description = "Developer Console Password (if set)"
  value       = "Use AWS Console password reset or IAM credentials file"
}
