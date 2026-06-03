# Kubernetes Manifests - Project Bedrock

This directory contains all Kubernetes manifests for the retail store application, organized by component.

## Directory Structure

```
k8s/
├── namespace/                      # Namespace definition
├── aws-load-balancer-controller/   # AWS Load Balancer Controller (CRITICAL)
├── ui/                             # UI frontend service
├── catalog/                        # Catalog service (RDS MySQL)
├── orders/                         # Orders service (RDS PostgreSQL)
├── carts/                          # Carts service (DynamoDB with IRSA)
├── checkout/                       # Checkout service
├── assets/                         # Assets service
├── rabbitmq/                       # RabbitMQ message broker (in-cluster)
├── redis/                          # Redis cache (in-cluster)
├── ingress/                        # ALB Ingress resource
└── README.md                       # This file
```

## Deployment

### Prerequisites
- EKS cluster running (terraform apply completed)
- kubectl configured to access cluster
- Kubernetes Secrets created by Terraform:
  - `catalog-db-credentials` in retail-app namespace
  - `orders-db-credentials` in retail-app namespace
- AWS Load Balancer Controller installed in kube-system

### Deploy All Components

```bash
# 1. Update kubeconfig
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1

# 2. Deploy AWS Load Balancer Controller FIRST (required for Ingress to work)
kubectl apply -f k8s/aws-load-balancer-controller/

# 3. Verify ALB controller pods are running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# 4. Deploy all other components
kubectl apply -f k8s/

# 5. Verify all resources created
kubectl get all -n retail-app
kubectl get ingress -n retail-app

# 6. Wait for pods to be ready
kubectl wait --for=condition=ready pod --all -n retail-app --timeout=300s

# 7. Get ALB DNS name (wait 2-3 minutes after ingress creation)
kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Deploy Individual Components

```bash
# Deploy specific component
kubectl apply -f k8s/ui/
kubectl apply -f k8s/catalog/
kubectl apply -f k8s/orders/
kubectl apply -f k8s/carts/
# ... etc
```

## Important Notes

### Data Persistence
- **Catalog (MySQL):** Credentials from `catalog-db-credentials` secret (created by Terraform)
- **Orders (PostgreSQL):** Credentials from `orders-db-credentials` secret (created by Terraform)
- **Carts (DynamoDB):** Uses IRSA (IAM Roles for Service Accounts) - no credentials needed
- **In-Cluster Services:** RabbitMQ and Redis use default credentials

### IRSA Configuration
The `carts` ServiceAccount is annotated with an IAM role ARN:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::839026370596:role/bedrock-carts-dynamodb-role
```

This allows the carts pods to access DynamoDB without hardcoded credentials.

### Service Discovery
Services communicate via Kubernetes DNS:
- Catalog: `http://catalog.retail-app.svc.cluster.local`
- Orders: `http://orders.retail-app.svc.cluster.local`
- Carts: `http://carts.retail-app.svc.cluster.local`
- etc.

### Ingress & ALB
The Ingress resource creates an AWS Application Load Balancer:
- Scheme: Internet-facing
- Target Type: IP
- Health Check Path: /health
- Routes all traffic to UI service (port 80)

## Verification

```bash
# Check all pods are running
kubectl get pods -n retail-app

# Check services exist
kubectl get svc -n retail-app

# Check ingress is provisioned
kubectl get ingress -n retail-app -o wide

# View pod logs
kubectl logs -n retail-app -l app=ui --tail=50

# Test connectivity to catalog
kubectl exec -it <ui-pod> -n retail-app -- curl http://catalog.retail-app.svc.cluster.local/health
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n retail-app
kubectl logs <pod-name> -n retail-app
```

### Database connection errors
```bash
# Verify secrets exist
kubectl get secrets -n retail-app
kubectl describe secret catalog-db-credentials -n retail-app

# Test connection from pod
kubectl exec -it <catalog-pod> -n retail-app -- bash
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD
```

### ALB not provisioning
```bash
# Check AWS Load Balancer Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Describe ingress for errors
kubectl describe ingress retail-app -n retail-app
```

## Cleanup

```bash
# Delete all manifests
kubectl delete -f k8s/

# Delete namespace (cascade deletes all resources)
kubectl delete namespace retail-app
```
