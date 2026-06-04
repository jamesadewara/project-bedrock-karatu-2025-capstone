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

# IMPORTANT: Clean out any lingering webhooks from previous runs BEFORE applying
# This prevents webhook conflicts if re-running after failed deployments
kubectl delete mutatingwebhookconfiguration aws-load-balancer-webhook-configuration --ignore-not-found 2>/dev/null || true
kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook-configuration --ignore-not-found 2>/dev/null || true

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
# Cycle worker nodes so they pick up the active Prefix Delegation limits
echo "Cycling nodes to apply Prefix Delegation..."
kubectl rollout restart daemonset aws-node -n kube-system

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
# Ensure you're in the project root directory
cd $(git rev-parse --show-toplevel) 2>/dev/null || cd ..

# Get your AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Update the carts service account manifest with your Account ID
sed -i "s|arn:aws:iam::.*:role/bedrock-carts-dynamodb-role|arn:aws:iam::${ACCOUNT_ID}:role/bedrock-carts-dynamodb-role|g" k8s/carts/serviceaccount.yaml

# Verify the replacement
grep "role-arn" k8s/carts/serviceaccount.yaml
# Should show: arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-carts-dynamodb-role

# NOTE: Carts image tag 0.6.0 may not be available in public.ecr.aws registry
# If ImagePullBackOff occurs, try:
#   - Using a different version tag (0.5.0, 0.4.0)
#   - Or comment out the carts deployment in k8s/carts/ if not critical to your requirements
```

## Phase 5: Deploy Application (kubectl manifests)

```bash
# Ensure you're in the project root directory
cd $(git rev-parse --show-toplevel) 2>/dev/null || cd ..

# Deploy all application manifests recursively
kubectl apply -R -f k8s/

echo "✓ Application resources deployed"

# Verify deployment status (do this first to see actual status)
kubectl get pods -n retail-app -o wide
kubectl get svc -n retail-app
kubectl get ingress -n retail-app

# NOTE: kubectl wait may hang indefinitely if deployments don't reach ready state
# This can happen if:
#   - Nodes don't have capacity (pending pods)
#   - Pod images fail to pull (ImagePullBackOff)
#   - Pods crash on startup (CrashLoopBackOff)
# In such cases, investigate with: kubectl describe pod <pod-name> -n retail-app
# and: kubectl logs <pod-name> -n retail-app

# Optionally wait for ALB ingress (less likely to timeout):
kubectl wait --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
  ingress/retail-app -n retail-app --timeout=300s || echo "⚠ ALB not provisioned yet"
```

**Note:** The `retail-app` namespace is created and managed by Terraform (`terraform/modules/eks/main.tf`). All application manifests include `namespace: retail-app` in their metadata and automatically deploy into this namespace.

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

if [ -z "$ALB_DNS" ]; then
  echo "⚠ ALB DNS not available yet. Check ingress status with: kubectl get ingress -n retail-app"
else
  echo "Testing ALB at: http://${ALB_DNS}"
  
  # Test health endpoint (may fail if pods not ready)
  curl -I http://${ALB_DNS}/health || echo "⚠ Health endpoint not responding (pods may not be ready)"
  
  # If health fails, verify pods are running:
  kubectl get pods -n retail-app -o wide
fi

# NOTE: If curl fails:
# - Check if pods are Running: kubectl get pods -n retail-app
# - Check pod logs: kubectl logs -n retail-app <pod-name>
# - Check ALB target health: aws elbv2 describe-target-health --target-group-arn <arn>
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
# Get the actual S3 bucket name (from terraform outputs)
BUCKET_NAME=$(terraform output -raw assets_bucket_name 2>/dev/null)

if [ -z "$BUCKET_NAME" ]; then
  echo "⚠ Could not retrieve bucket name from terraform. Check terraform outputs:"
  terraform output assets_bucket_name
  exit 1
fi

# Upload a test file to S3 (triggers Lambda)
echo "Uploading test file to s3://${BUCKET_NAME}/"
echo "test content" > test-file.txt
aws s3 cp test-file.txt s3://${BUCKET_NAME}/

# Check Lambda logs (should see invocation)
aws logs tail /aws/lambda/bedrock-asset-processor --follow

# Verify Lambda was invoked
aws lambda get-function-configuration \
  --function-name bedrock-asset-processor \
  --query 'LastModified'
  
# Cleanup
rm -f test-file.txt
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

# Delete all Kubernetes application resources
kubectl delete -R -f k8s/ --ignore-not-found

echo "✓ Application resources deleted"

# Destroy all Terraform infrastructure (will also delete the retail-app namespace)
cd terraform
terraform destroy -auto-approve

echo "✓ Infrastructure destroyed"

# Optional: Delete Terraform state bucket (one-time only, if no longer needed)
# aws s3 rm s3://karatu-terraform-state-jamesadewara --recursive
# aws s3api delete-bucket --bucket karatu-terraform-state-jamesadewara
```

**Note:** The `retail-app` namespace is managed by Terraform and will be automatically deleted as part of `terraform destroy`.

## Troubleshooting

### Pods not starting / stuck in Pending
```bash
# Check pod scheduling status
kubectl describe pod <pod-name> -n retail-app

# Common cause: Not enough node capacity
# Check node resource usage:
kubectl top nodes
kubectl top pods -n retail-app

# If nodes at capacity, increase desired node count:
aws eks update-nodegroup-config \
  --cluster-name project-bedrock-cluster \
  --nodegroup-name project-bedrock-cluster-nodes \
  --scaling-config desiredSize=15,minSize=2,maxSize=20
```

### Pods crashing (CrashLoopBackOff)
```bash
# Get detailed pod events
kubectl describe pod <pod-name> -n retail-app

# View pod logs
kubectl logs <pod-name> -n retail-app --previous  # Shows last run's logs
kubectl logs <pod-name> -n retail-app              # Shows current logs

# Common issues:
# - Migrations failing (catalog): Database connectivity or RDS timeout
# - Image not found (carts): Invalid image tag in ECR
# - Missing config/secrets: Check if secrets exist with kubectl get secrets -n retail-app
```

### Database connection errors (timeout)
```bash
# 1. Verify secrets exist and contain correct endpoints
kubectl get secrets -n retail-app
kubectl get secret catalog-db-credentials -n retail-app -o yaml

# 2. Verify RDS security group allows traffic from EKS nodes
SECURITY_GROUP=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=*rds*" --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 describe-security-groups --group-ids $SECURITY_GROUP

# 3. Test database connectivity from pod
kubectl exec -it $(kubectl get pods -n retail-app -l app=catalog -o jsonpath='{.items[0].metadata.name}') -n retail-app -- bash
mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD -e "SELECT 1;"

# 4. If migrations timeout, increase the deployment's timeout or disable migrations
kubectl set env deployment/catalog DB_MIGRATION_DISABLE=true -n retail-app
kubectl rollout restart deployment/catalog -n retail-app
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
# Get bucket name from terraform
BUCKET_NAME=$(terraform output -raw assets_bucket_name)

# Verify S3 event notification is configured
aws s3api get-bucket-notification-configuration --bucket $BUCKET_NAME

# Check Lambda permissions
aws lambda get-policy --function-name bedrock-asset-processor

# Test Lambda manually
aws lambda invoke --function-name bedrock-asset-processor /tmp/response.json
cat /tmp/response.json
```

### Carts ImagePullBackOff - Image not found
```bash
# The public.ecr.aws image may not exist with tag 0.6.0
# Options:
# 1. Try different version:
sed -i 's|:0.6.0|:0.5.0|g' k8s/carts/deployment.yaml
kubectl apply -f k8s/carts/deployment.yaml

# 2. Or disable carts deployment if not critical:
kubectl delete deployment carts -n retail-app

# 3. Check what tags are available (if accessible):
aws ecr describe-images --repository-name aws-containers/retail-store-sample-carts \
  --registry-id public --region us-east-1
```

## Useful Commands

```bash
# Get all resources in retail-app namespace
kubectl get all -n retail-app

# Stream logs from all pods
kubectl logs -n retail-app --all-containers=true -f

# Get detailed pod information
kubectl get pods -n retail-app -o wide -w # check in real time

# Check cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Test service connectivity
kubectl exec -it <pod> -n retail-app -- curl http://catalog.retail-app.svc.cluster.local/health

# Monitor CloudWatch logs in real-time
aws logs tail /aws/eks/project-bedrock-cluster/container-logs --follow
```

---

## Free Tier Considerations

This project uses AWS Free Tier resources:
- **EKS Cluster**: No charge for control plane
- **EC2 Nodes**: t3.micro/t2.micro (750 hours/month free)
- **RDS**: 750 hours/month free (MySQL 8.0, PostgreSQL 16.3)
- **ALB**: Partial free tier (730 hours/month)
- **S3**: 5GB storage free
- **Lambda**: 1 million requests/month free
- **CloudWatch Logs**: 5GB ingestion free

⚠️ **Scaling caveat**: The Free Tier account may have limits preventing scaling beyond 6-8 small instances. If you need more capacity, upgrade to a paid account or request a limit increase from AWS Support.

---

**Last Updated:** June 4, 2026