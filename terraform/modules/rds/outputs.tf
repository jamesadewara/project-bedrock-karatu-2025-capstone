output "catalog_endpoint" {
  value = aws_db_instance.catalog.address
}

output "catalog_port" {
  value = aws_db_instance.catalog.port
}

output "orders_endpoint" {
  value = aws_db_instance.orders.address
}

output "orders_port" {
  value = aws_db_instance.orders.port
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}