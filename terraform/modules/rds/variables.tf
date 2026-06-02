variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs"
  type        = list(string)
}

variable "eks_security_group_id" {
  description = "EKS Node Security Group ID"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS Cluster Name"
  type        = string
}

variable "db_username" {
  description = "DB Username"
  type        = string
}

variable "db_password" {
  description = "DB Password"
  type        = string
  sensitive   = true
}

variable "db_name_catalog" {
  description = "Catalog Database Name"
  type        = string
}

variable "db_name_orders" {
  description = "Orders Database Name"
  type        = string
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "aws_db_instance_catalog_instance_class" {
  description = "Catalog Database Instance Class"
  type        = string
  default     = "db.t3.micro"
}

variable "aws_db_instance_orders_instance_class" {
  description = "Orders Database Instance Class"
  type        = string
  default     = "db.t3.micro"
}
