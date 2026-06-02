# Architecture Diagram

Create your architecture diagram using:
- Draw.io (diagrams.net)
- Lucidchart
- PowerPoint / Google Slides

Required elements to show:
1. VPC with 2 AZs (public + private subnets)
2. Internet Gateway + NAT Gateways
3. EKS Cluster in private subnets
4. ALB in public subnets
5. RDS MySQL + PostgreSQL in private subnets
6. DynamoDB (managed service)
7. S3 Bucket + Lambda + CloudWatch flow
8. GitHub Actions CI/CD pipeline
9. IAM user mapping to K8s RBAC

Export as PNG and save to: docs/architecture-diagram.png
