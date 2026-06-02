# ============================================================
# OUTPUTS - Required for Grading Script
# ============================================================

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

output "acm_certificate_arn" {
  description = "ACM Certificate ARN for ALB HTTPS"
  value       = aws_acm_certificate.main.arn
}

output "acm_validation_cname_records" {
  description = "ACM Validation CNAME Records to add in Namecheap"
  value = [
    for dvo in aws_acm_certificate.main.domain_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS Name"
  value       = "Run this command to get the ALB DNS: kubectl get ingress -n ${var.app_namespace}"
}

output "domain_name" {
  description = "Your domain name for the retail store"
  value       = var.domain_name
}

output "app_url" {
  description = "URL to access the retail store application"
  value       = "https://${var.domain_name}"
}

output "namecheap_cname_instructions" {
  description = "Steps to configure Namecheap with CNAME"
  value       = <<-EOT
    Step 1: Add ACM validation CNAME records in Namecheap using the values from the acm_validation_cname_records output.
    Step 2: Wait for ACM validation to complete.
    Step 3: Add ALB CNAME record in Namecheap pointing your domain to the ALB DNS name (retrieve via kubectl get ingress).
  EOT
}
