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

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "aws_eks_node_group_instance_types" {
  description = "EKS Node Group Instance Types"
  type        = list(string)
  default     = ["t2.micro"]
}

variable "dev_user_arn" {
  description = "IAM ARN of the developer user to map in aws-auth"
  type        = string
}
