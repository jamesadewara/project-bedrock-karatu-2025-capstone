# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.eks_cluster_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.eks_cluster_name}-db-subnet-group"
  })
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.eks_cluster_name}-rds-sg"
  description = "Security group for RDS databases"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id, var.cluster_security_group_id]
    description     = "MySQL from EKS nodes"
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id, var.cluster_security_group_id]
    description     = "PostgreSQL from EKS nodes"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.eks_cluster_name}-rds-sg"
  })
}

# Parameter Group for MySQL
resource "aws_db_parameter_group" "mysql" {
  family = "mysql8.0"
  name   = "${var.eks_cluster_name}-mysql-params"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = var.common_tags
}

# Parameter Group for PostgreSQL
resource "aws_db_parameter_group" "postgres" {
  family = "postgres16"
  name   = "${var.eks_cluster_name}-postgres-params"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = var.common_tags
}

resource "aws_db_instance" "catalog" {
  identifier = "${var.eks_cluster_name}-catalog"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.aws_db_instance_catalog_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp2" # gp2 is cheaper than gp3 for small instances
  storage_encrypted     = true

  db_name  = var.db_name_catalog
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.mysql.name

  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 1

  tags = merge(var.common_tags, {
    Name    = "${var.eks_cluster_name}-catalog-mysql"
    Service = "catalog"
  })
}

resource "aws_db_instance" "orders" {
  identifier = "${var.eks_cluster_name}-orders"

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.aws_db_instance_orders_instance_class # FREE TIER ELIGIBLE

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name_orders
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  publicly_accessible     = false
  multi_az                = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 1

  tags = merge(var.common_tags, {
    Name    = "${var.eks_cluster_name}-orders-postgres"
    Service = "orders"
  })
}