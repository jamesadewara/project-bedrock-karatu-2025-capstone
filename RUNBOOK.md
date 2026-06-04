# Project Bedrock - Deployment Runbook
 
## Prerequisites
- AWS CLI configured with appropriate credentials
- kubectl installed (v1.28+)
- Terraform installed (v1.10+)
- jq (JSON processor)

## Phase 1: Infrastructure Provisioning (Terraform)

```bash
cd terraform
# Step 1a: Download AWS Load Balancer Controller IAM Policy
curl -s https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json \
  > modules/eks/alb_controller_policy.json

echo "✓ ALB controller policy downloaded"

# Step 1b: Download ALB controller Helm chart locally
mkdir -p modules/eks/charts
helm repo add eks https://aws.github.io/eks-charts
helm pull eks/aws-load-balancer-controller --untar --untardir modules/eks/charts

echo "✓ ALB controller Helm chart downloaded"

# Step 1c: Provision infrastructure (one-time setup)
aws s3api create-bucket \
  --bucket karatu-terraform-state-jamesadewara \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket karatu-terraform-state-jamesadewara \
  --versioning-configuration Status=Enabled

terraform init
terraform plan
terraform apply -auto-approve

echo "✓ Infrastructure provisioned"

# Step 1d: Save outputs and retrieve Account ID
terraform output -json > ../grading.json
terraform output -json | jq '{cluster_endpoint, cluster_name, region, vpc_id, assets_bucket_name}'

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"
```

## Phase 2: Cluster Access Configuration

```bash
# Update kubeconfig to connect to the EKS cluster
aws eks update-kubeconfig \
  --name project-bedrock-cluster \
  --region us-east-1

# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes

# Verify key infrastructure components are deployed
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n amazon-cloudwatch -l app.kubernetes.io/name=aws-for-fluent-bit
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node

echo "✓ Cluster access verified"
```

## Phase 3: Verify Kubernetes Secrets

Terraform created the database credentials in the retail-app namespace:

```bash
# Verify secrets exist
kubectl get secrets -n retail-app
```

## Phase 4: Update Carts ServiceAccount with Your AWS Account ID

The carts ServiceAccount uses IRSA (IAM Roles for Service Accounts) to access DynamoDB.

```bash
# Get your AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update the carts service account manifest with your Account ID
sed -i "s|arn:aws:iam::.*:role/bedrock-carts-dynamodb-role|arn:aws:iam::${ACCOUNT_ID}:role/bedrock-carts-dynamodb-role|g" k8s/carts/serviceaccount.yaml

# Verify the replacement
grep "role-arn" k8s/carts/serviceaccount.yaml
# Should show: arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-carts-dynamodb-role
```

## Phase 5: Deploy Application (kubectl manifests)

```bash
# Ensure you're in the project root directory
cd $(git rev-parse --show-toplevel) 2>/dev/null || cd ..

# Deploy namespace first (prerequisite for all other resources)
kubectl apply -f k8s/namespace/

# Deploy all components recursively (safe after namespace exists)
kubectl apply -R -f k8s/

echo "✓ Application resources deployed"

# Wait for all deployments to be ready (may take 2-3 minutes)
kubectl wait --for=condition=available deployment --all -n retail-app --timeout=300s

# Verify deployment status
kubectl get pods -n retail-app -o wide
kubectl get svc -n retail-app
kubectl get ingress -n retail-app
```

## Phase 6: Verify ALB is Provisioned

The AWS Load Balancer Controller creates an Application Load Balancer when the Ingress is applied.

```bash
# Wait for ALB DNS name to be provisioned (may take 2-3 minutes)
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
  ingress/retail-app -n retail-app --timeout=300s

# Get the ALB DNS name
ALB_DNS=$(kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "✓ Application URL: http://${ALB_DNS}"
```

## Phase 7: Test Application Accessibility

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test health endpoint
curl -I http://${ALB_DNS}/health

# Expected output: HTTP/1.1 200 OK
```

## Phase 8: Verify Observability (CloudWatch Logs)

```bash
# View container logs shipped by FluentBit
aws logs tail /aws/eks/project-bedrock-cluster/containers --follow

# View EKS control plane logs (API, audit, etc.)
aws logs tail /aws/eks/project-bedrock-cluster/api --follow
```

## Phase 9: Test Serverless Extension (S3-Lambda)

```bash
# Upload a test file to S3 (triggers Lambda)
aws s3 cp test-image.jpg s3://bedrock-assets-alt-soe-025-3359/

# Check Lambda logs (should see "Image received: test-image.jpg")
aws logs tail /aws/lambda/bedrock-asset-processor --follow

# Verify Lambda was invoked
aws lambda get-function-configuration \
  --function-name bedrock-asset-processor \
  --query 'LastModified'
```

## Phase 10: Verify Developer Access (bedrock-dev-view)

### AWS Console Access (Read-Only)
The bedrock-dev-view user has:
- ReadOnlyAccess to AWS Console
- s3:PutObject permission on bedrock-assets-* bucket only

### Kubernetes Access (Read-Only)
The bedrock-dev-view user is mapped to the Kubernetes "view" ClusterRole:

```bash
# Test: bedrock-dev-view can READ pods (should succeed)
# kubectl get pods -n retail-app

# Test: bedrock-dev-view can WRITE to S3 (should succeed)
# aws s3 cp file.txt s3://bedrock-assets-alt-soe-025-3359/

# Test: bedrock-dev-view CANNOT delete pods (should fail with RBAC error)
# kubectl delete pod <pod-name> -n retail-app
# Expected: Error from server (Forbidden): pods is forbidden...
```

## Phase 11: Update grading.json with ALB DNS

```bash
# Ensure you're in the project root directory
cd $(git rev-parse --show-toplevel) 2>/dev/null || cd ..

# Get ALB DNS name
ALB_DNS=$(kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Update grading.json with ALB DNS
jq ".alb_dns_name = \"$ALB_DNS\"" grading.json > grading.json.tmp && mv grading.json.tmp grading.json

# Verify final grading.json
jq '{cluster_endpoint, cluster_name, region, vpc_id, assets_bucket_name, alb_dns_name}' grading.json
```

## Phase 12: Cleanup (CAUTION - Deletes all resources)

```bash
# Ensure you're in the project root directory
cd $(git rev-parse --show-toplevel) 2>/dev/null || cd ..

# Delete all Kubernetes resources and namespace
kubectl delete -R -f k8s/
kubectl delete namespace retail-app --wait=false

echo "✓ Kubernetes resources deleted"

# Destroy all Terraform infrastructure
cd terraform
terraform destroy -auto-approve

echo "✓ Infrastructure destroyed"

# Optional: Delete Terraform state bucket (one-time only, if no longer needed)
# aws s3 rm s3://karatu-terraform-state-jamesadewara --recursive
# aws s3api delete-bucket --bucket karatu-terraform-state-jamesadewara
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

# Verify RDS security group allows traffic from EKS nodes
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Test database connectivity from pod
kubectl exec -it <catalog-pod> -n retail-app -- bash
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD
```

### ALB not provisioning
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Check ingress events
kubectl describe ingress retail-app -n retail-app

# Verify public subnets are tagged for ALB discovery
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/role/elb,Values=1" \
  --query 'Subnets[*].[SubnetId, Tags]'
```

### CloudWatch logs not appearing
```bash
# Verify CloudWatch Observability add-on pod
kubectl get pods -n amazon-cloudwatch

# Check CloudWatch add-on logs
kubectl logs -n amazon-cloudwatch -l app=cloudwatch-observability --tail=20

# Verify CloudWatch log groups were created
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/project-bedrock-cluster"
```

### Lambda not triggering on S3 upload
```bash
# Verify S3 event notification is configured
aws s3api get-bucket-notification-configuration --bucket bedrock-assets-alt-soe-025-3359

# Check Lambda permissions
aws lambda get-policy --function-name bedrock-asset-processor

# Test Lambda manually
aws lambda invoke --function-name bedrock-asset-processor /tmp/response.json
cat /tmp/response.json
```

## Useful Commands

```bash
# Get all resources in retail-app namespace
kubectl get all -n retail-app

# Stream logs from all pods
kubectl logs -n retail-app --all-containers=true -f

# Get detailed pod information
kubectl get pods -n retail-app -o wide

# Check cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Test service connectivity
kubectl exec -it <pod> -n retail-app -- curl http://catalog.retail-app.svc.cluster.local/health

# Monitor CloudWatch logs in real-time
aws logs tail /aws/eks/project-bedrock-cluster/container-logs --follow
```

---

**Last Updated:** June 3, 2026