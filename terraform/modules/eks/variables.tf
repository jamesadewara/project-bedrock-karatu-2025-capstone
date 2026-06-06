variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes Version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public Subnet IDs"
  type        = list(string)
}

variable "app_namespace" {
  description = "Application Namespace"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
}

variable "eks_public_access_cidrs" {
  description = "EKS API endpoint public access CIDR blocks (for security: restrict to your IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "aws_eks_node_group_instance_types" {
  description = "EKS Node Group Instance Types"
  type        = list(string)
  default     = ["t3.small"] # "t3.small"
}

variable "dev_user_arn" {
  description = "IAM ARN of the developer user to map in aws-auth"
  type        = string
}

variable "db_username" {
  description = "RDS Master Username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS Master Password"
  type        = string
  sensitive   = true
}

variable "db_name_catalog" {
  description = "Catalog database name"
  type        = string
}

variable "db_name_orders" {
  description = "Orders database name"
  type        = string
}

variable "github_actions_role_arn" {
  description = "IAM ARN of the GitHub Actions role to map in aws-auth"
  type        = string
}
