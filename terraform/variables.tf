variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
  default     = "project-bedrock-cluster"
}

variable "vpc_name" {
  description = "VPC Name Tag"
  type        = string
  default     = "project-bedrock-vpc"
}

variable "app_namespace" {
  description = "Kubernetes Application Namespace"
  type        = string
  default     = "retail-app"
}

variable "iam_user_dev" {
  description = "Developer IAM User Name"
  type        = string
  default     = "bedrock-dev-view"
}

variable "s3_bucket_name" {
  description = "S3 Assets Bucket Name"
  type        = string
  default     = "bedrock-assets-alt-soe-025-3359"
}

variable "lambda_function_name" {
  description = "Lambda Function Name"
  type        = string
  default     = "bedrock-asset-processor"
}

variable "project_tag" {
  description = "Project Tag Value"
  type        = string
  default     = "karatu-2025-capstone"
}

variable "eks_version" {
  description = "EKS Kubernetes Version"
  type        = string
  default     = "1.32"
}

variable "eks_public_access_cidrs" {
  description = "EKS API endpoint public access CIDR blocks - RESTRICT TO YOUR IP FOR SECURITY (default allows all)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_username" {
  description = "RDS Master Username"
  type        = string
  default     = "bedrockadmin"
  sensitive   = true
}

variable "db_name_catalog" {
  description = "Catalog Database Name"
  type        = string
  default     = "catalogdb"
}

variable "db_name_orders" {
  description = "Orders Database Name"
  type        = string
  default     = "ordersdb"
}

variable "availability_zones" {
  description = "Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDRs"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private Subnet CIDRs"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "aws_secretsmanager_secret_db_recovery_window_in_days" {
  description = "Days to retain deleted Secrets Manager secrets (7-30 recommended for recovery)"
  type        = number
  default     = 0 # normally 7 days is ideal --- set to 0 for immediate deletion during development
}

variable "domain_name" {
  description = "The custom domain name to request an ACM certificate for (e.g. example.com). Leave empty to skip ACM."
  type        = string
  default     = "spatialdesign3d.site"
}

variable "github_repo" {
  description = "The GitHub repository in format owner/repo-name for OIDC trust role"
  type        = string
  default     = "jamesadewara/project-bedrock-karatu-2025-capstone"
}