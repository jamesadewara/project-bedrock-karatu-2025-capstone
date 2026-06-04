# Project Bedrock - EKS Microservices with Managed Data Layer

A production-grade Kubernetes deployment on AWS EKS featuring a retail microservices application with managed AWS data services (RDS, DynamoDB), in-cluster messaging (RabbitMQ), and in-cluster caching (Redis).

## Overview

**Project Bedrock** implements a complete cloud-native architecture using:

- **Infrastructure as Code:** Terraform with modular design (VPC, EKS, RDS, DynamoDB)
- **Container Orchestration:** Kubernetes (EKS) with kubectl-only deployments
- **Managed Data Layer:** 
  - RDS MySQL 8.0 (Catalog database)
  - RDS PostgreSQL 16.3 (Orders database)
  - DynamoDB on-demand (Shopping carts with PITR)
- **Application Components:** 6 microservices + 2 infrastructure services (RabbitMQ, Redis)
- **Ingress:** AWS Application Load Balancer via Kubernetes controller
- **Observability:** CloudWatch container logging with EKS add-on
- **CI/CD:** GitHub Actions for Terraform plan/apply

## Prerequisites

- **AWS Account:** Configured with appropriate IAM permissions
- **Tools:**
  - AWS CLI v2.x
  - Terraform v1.10+
  - kubectl v1.30+
  - helm (optional, for verification only - NOT used in deployment)
  - git

## Quick Start

### 1. Provision Infrastructure

```bash
cd terraform
terraform init
terraform plan  # Review changes
terraform apply  # Provision all AWS resources
```

### 2. Configure Kubernetes Access

```bash
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
kubectl get nodes  # Verify cluster access
```

### 3. Deploy Application

```bash
# Deploy ALB controller first (required for ingress)
kubectl apply -f k8s/aws-load-balancer-controller/

# Deploy all application components
kubectl apply -f k8s/

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod --all -n retail-app --timeout=300s
```

### 4. Access Application

```bash
# Get ALB DNS name (wait 2-3 minutes for ALB provisioning)
kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Open in browser: http://<ALB_DNS_NAME>
```

## Architecture

### Components

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

```
User Browser
    ↓
AWS ALB (created by Ingress)
    ↓
Kubernetes UI Service (Port 80)
    ↓
    ├→ Catalog Service → RDS MySQL
    ├→ Orders Service → RDS PostgreSQL
    ├→ Carts Service → DynamoDB (IRSA)
    ├→ Checkout Service → RabbitMQ
    └→ Assets Service → S3 (via Lambda processor)
```

## Directory Structure

```
project-bedrock-karatu-2025-capstone/
├── terraform/                          # Infrastructure as Code
│   ├── main.tf                        # Root module
│   ├── providers.tf                   # AWS, Kubernetes, TLS providers
│   ├── backend.tf                     # Remote state backend
│   ├── variables.tf                   # Input variables
│   ├── outputs.tf                     # Stack outputs
│   └── modules/
│       ├── vpc/                       # VPC configuration
│       ├── eks/                       # EKS cluster & add-ons
│       ├── rds/                       # RDS databases (MySQL, PostgreSQL)
│       └── ...
├── k8s/                               # Kubernetes manifests (kubectl-only)
│   ├── namespace/                     # retail-app namespace
│   ├── aws-load-balancer-controller/ # ALB controller (4 manifests)
│   ├── ui/                           # UI frontend service
│   ├── catalog/                      # Catalog service
│   ├── orders/                       # Orders service
│   ├── carts/                        # Carts service with IRSA
│   ├── checkout/                     # Checkout service
│   ├── assets/                       # Assets service
│   ├── rabbitmq/                     # RabbitMQ broker
│   ├── redis/                        # Redis cache
│   ├── ingress/                      # ALB ingress rule
│   └── README.md                     # Kubernetes deployment guide
├── lambda/                            # Serverless extension
│   ├── index.py                      # S3 asset processor
│   └── requirements.txt
├── RUNBOOK.md                        # Complete deployment guide (12 phases)
├── PROJECT_REQUIREMENTS.md           # Project specification & grading criteria
├── grading.json                      # Grading script configuration
└── LICENSE
```

## Key Features

### 1. **Infrastructure as Code (Terraform)**
- Modular design with VPC, EKS, RDS, and DynamoDB modules
- Remote state backend with state locking
- Comprehensive IAM roles and policies

### 2. **Kubernetes Deployment (kubectl-only)**
- Component-based manifest organization
- No Helm - all deployment via `kubectl apply -f k8s/`
- Proper namespace isolation (retail-app)
- Environment-based configuration via Kubernetes Secrets

### 3. **Managed Data Services**
- RDS MySQL for catalog (managed backups, automatic failover)
- RDS PostgreSQL for orders (managed backups, automatic failover)
- DynamoDB for carts (on-demand billing, PITR enabled)
- Secrets Manager for credential rotation

### 4. **AWS Load Balancer Controller**
- Kubernetes-native ALB provisioning
- Deployed via kubectl manifests (NOT Helm)
- IRSA (IAM Roles for Service Accounts) for secure AWS access

### 5. **Observability**
- CloudWatch container logs via amazon-cloudwatch-observability add-on
- EKS control plane logging
- 7-day log retention

### 6. **Security**
- Private EKS nodes in private subnets
- IRSA for pod-to-AWS authentication (carts service ↔ DynamoDB)
- Kubernetes service account annotations
- Managed secrets for database credentials

### 7. **Serverless Extension**
- Lambda function for S3 asset processing
- S3 trigger on file uploads
- bedrock-dev-view IAM user for read-only access

## Deployment Workflow

See [RUNBOOK.md](RUNBOOK.md) for complete 12-phase deployment guide including:
1. Infrastructure provisioning
2. Cluster access configuration
3. Secrets preparation
4. IRSA configuration for carts
5. Application deployment
6. ALB provisioning verification
7. Application testing
8. Observability verification
9. Serverless extension testing
10. Developer access verification
11. Grading configuration
12. Cleanup procedures

## Verification Commands

```bash
# Check cluster health
kubectl get nodes -o wide
kubectl get pods -A

# Check application namespace
kubectl get all -n retail-app

# Check ALB ingress
kubectl get ingress -n retail-app
kubectl describe ingress retail-app -n retail-app

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check container logs
kubectl logs -n retail-app -l app=ui --tail=50

# Verify IRSA configuration (carts service)
kubectl describe sa carts -n retail-app
```

## Troubleshooting

### ALB Not Provisioning
```bash
# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -f

# Verify ingress annotation
kubectl get ingress retail-app -n retail-app -o yaml | grep -A5 annotations
```

### Pods Not Starting
```bash
# Check pod events
kubectl describe pod <pod-name> -n retail-app

# Check CloudWatch logs
aws logs tail /aws/eks/project-bedrock-cluster/container-logs --follow
```

### Database Connection Issues
```bash
# Verify secrets exist
kubectl get secrets -n retail-app

# Check secret values
kubectl get secret catalog-db-credentials -n retail-app -o jsonpath='{.data.host}' | base64 -d

# Test RDS connectivity from pod
kubectl exec -it <pod-name> -n retail-app -- \
  mysql -h <db-host> -u <db-user> -p<db-password> -e "SELECT VERSION();"
```

### AWS Service Quotas - vCPU Limit
If pods remain in Pending state with "Too many pods" messages:
1. Go to [AWS Service Quotas Console](https://console.aws.amazon.com/servicequotas)
2. Search: "EC2 On-Demand Standard instances"
3. Request quota increase to 32 vCPUs
4. After approval, scale node group to desired size

## Cleanup

To destroy all resources and cleanup:

```bash
# Delete Kubernetes resources
kubectl delete -f k8s/

# Destroy Terraform infrastructure
cd terraform
terraform destroy
```

## AWS Service Quotas - vCPU Limit Increase

The default AWS Free Tier account allows **8 vCPUs** for On-Demand t3/t2 instances. The Project Bedrock infrastructure initially provisions 6 EC2 nodes (t3.micro), which already uses 12 vCPUs—exceeding the Free Tier limit by 50%. **To deploy the full application stack, you must request a vCPU Limit Increase** through AWS Service Quotas for **Amazon Elastic Compute Cloud (Amazon EC2)** → **Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances**. Request an increase to **32 vCPUs** to allow full cluster scaling. The request typically approves within hours. Once approved, scale the EKS node group: `aws eks update-nodegroup-config --cluster-name project-bedrock-cluster --nodegroup-name project-bedrock-cluster-nodes --scaling-config desiredSize=6,minSize=2,maxSize=15 --region us-east-1`. This enables all application pods to schedule across the cluster.

## Project Constraints

✅ **Requirements Met:**
- Kubernetes deployment via kubectl manifests ONLY (no Helm)
- Managed AWS data layer (RDS MySQL/PostgreSQL, DynamoDB)
- Component-based k8s directory structure
- AWS Load Balancer Controller deployed via kubectl
- CloudWatch container logging
- IRSA for carts service DynamoDB access
- Terraform infrastructure as code
- Production-ready with proper resource limits and health checks

## Student Information

- **Student ID:** ALT/SOE/025/3359
- **AWS Account:** 839026370596
- **Region:** us-east-1
- **EKS Cluster:** project-bedrock-cluster
- **Namespace:** retail-app
- **IAM User (Read-Only):** bedrock-dev-view

## References

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Support

For issues or questions, refer to:
1. [RUNBOOK.md](RUNBOOK.md) - Deployment procedures
2. [PROJECT_REQUIREMENTS.md](PROJECT_REQUIREMENTS.md) - Project specification
3. [k8s/README.md](k8s/README.md) - Kubernetes manifest guide

---

**Last Updated:** June 3, 2026  
**Deployment Method:** kubectl manifests only (no Helm)  
**Infrastructure:** Terraform 1.10+
