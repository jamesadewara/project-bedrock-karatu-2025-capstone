# Project Bedrock - EKS Microservices with Managed Data Layer

A production-grade Kubernetes deployment on AWS EKS featuring a retail microservices application with managed AWS data services (RDS, DynamoDB), in-cluster messaging (RabbitMQ), and in-cluster caching (Redis)
## Overview

**Project Bedrock** implements a complete cloud-native architecture using:

- **Infrastructure as Code:** Terraform with modular design (VPC, EKS, RDS, DynamoDB)
- **Container Orchestration:** Kubernetes (EKS)
- **Managed Data Layer:** 
  - RDS MySQL 8.0 (Catalog database)
  - RDS PostgreSQL 16.3 (Orders database)
  - DynamoDB on-demand (Shopping carts with PITR)
- **Ingress & Security:** AWS Application Load Balancer (ALB) via Kubernetes controller, ACM Certificates, and Automatic HTTP-to-HTTPS redirects.
- **CI/CD:** Fully automated GitHub Actions pipelines for `terraform plan` and `terraform apply` with integrated security scanning (tfsec & Checkov).

## Quick Start

The infrastructure is fully automated via GitHub Actions.
  
### 1. Provision Infrastructure
Simply push your changes to the `main` or `staging` branch. The GitHub Actions pipeline will:
1. Run security scans (tfsec & Checkov).
2. Provision the AWS EKS Cluster and Node Groups (Phase 1).
3. Provision all dependencies, IAM roles, RDS databases, DynamoDB, and the ALB Controller (Phase 2).
4. Automatically commit the `grading.json` output back to the repository.

### 2. Configure Local Access
```bash
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
kubectl get nodes
```

### 3. Deploy Application Manifests
```bash
kubectl apply -f k8s/
kubectl wait --for=condition=ready pod --all -n retail-app --timeout=300s
```

### 4. Setup S3 Assets
The UI requires product images to serve correctly. Run the automated setup script to download and push them to your S3 bucket:
```bash
chmod +x scripts/setup-images.sh
bash scripts/setup-images.sh
```

## Architecture

| Component | Type | Purpose |
|-----------|------|---------|
| **UI** | Frontend | Retail store interface |
| **Catalog** | Service | Product catalog (RDS MySQL) |
| **Orders** | Service | Order management (RDS PostgreSQL) |
| **Carts** | Service | Shopping carts (DynamoDB with IRSA) |
| **Checkout** | Service | Checkout workflow |
| **Assets** | Service | Static asset serving |
| **RabbitMQ** | Infrastructure | Message broker for async workflows |
| **Redis** | Infrastructure | In-cluster caching layer |

### Data Flow

```text
User Browser
    ↓
AWS ALB (HTTPS port 443)
    ↓
Kubernetes UI Service (Port 80)
    ↓
    ├→ Catalog Service → RDS MySQL
    ├→ Orders Service → RDS PostgreSQL
    ├→ Carts Service → DynamoDB (IRSA)
    ├→ Checkout Service → RabbitMQ
    └→ Assets Service → S3 (via Lambda processor)
```

## Support & Documentation

For detailed procedures and issue resolution, refer to the following guides:
1. **[RUNBOOK.md](RUNBOOK.md)** - Comprehensive 12-phase deployment and verification procedures.
2. **[TROUBLESHOOT.md](TROUBLESHOOT.md)** - Solutions for common issues (Pods crashing, Database connections, ALB health checks).
---

**Last Updated:** June 2026  
**Infrastructure:** Terraform >= 1.5.0  
**AWS CLI:** v2.34.63  
**Helm:** v4.2.0  
**kubectl:** v1.35.5 (client) / v1.34.7-eks-40737a8 (server)  
**Kustomize:** v5.7.1  
**License:** MIT ([LICENSE](LICENSE))
