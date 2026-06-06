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

## Phase 4: Kubernetes Resources (Now Managed by Terraform)

The following Kubernetes resources are now created automatically by Terraform:

- **ServiceAccount**: `carts` (with IRSA annotation for DynamoDB access)
- **Secrets**: `catalog-db-credentials`, `orders-db-credentials`, `rabbitmq-credentials`
- **ExternalName Services**: `catalog-db`, `orders-db` (pointing to RDS endpoints)

**No manual updates needed!** Terraform dynamically:
1. Generates IRSA annotations using the actual account ID
2. Creates RabbitMQ credentials (random 32-char password)
3. Maps RDS endpoints without hardcoding

Verify all resources are created:

```bash
kubectl get sa -n retail-app carts
kubectl get secret -n retail-app catalog-db-credentials orders-db-credentials rabbitmq-credentials
kubectl get svc -n retail-app catalog-db orders-db
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
watch kubectl get pods -n retail-app
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

## Phase 6: Populate S3 Assets & Verify ALB is Provisioned

### ⚠️ CRITICAL: S3 Asset Population MUST Run After Phase 5

This is the most common failure point in the deployment. After you deploy the application in Phase 5, the S3 bucket is empty, which causes:
- ❌ Assets pod fails to serve images
- ❌ UI pod fails readiness probes
- ❌ RabbitMQ pod fails readiness probes
- ❌ All pods stuck at 0/1 Ready
- ❌ ALB returns 503 Service Unavailable

**Solution: Populate S3 bucket IMMEDIATELY after Phase 5 completes**

### Step 6a: Download & Upload Official Retail Store Images (Recommended)

This is the **official and recommended approach**. It downloads real product images from the AWS retail store sample app GitHub repository.

#### Run the Automated Setup Script

```bash
# Make the script executable (first time only)
chmod +x scripts/setup-images.sh

# Run the setup script
bash scripts/setup-images.sh
```

**What this script does:**
1. ✅ Verifies AWS credentials and kubectl connectivity
2. ✅ Creates/updates local `assets-images/` directory (ignored by git)
3. ✅ Downloads official images from GitHub release (v1.2.1)
4. ✅ Extracts all images locally
5. ✅ Uploads everything to S3 bucket
6. ✅ Restarts deployments (ui, assets, rabbitmq)

**Expected output:**
```
Step 1: Verifying Prerequisites
✅ AWS CLI installed
✅ Download tool available: wget
✅ kubectl installed
✅ AWS Account ID: 123456789012
✅ S3 bucket accessible: s3://bedrock-assets-alt-soe-025-3359/

Step 2: Setting Up Local Assets Directory
✅ Created assets directory: /home/WORKSPACE/project-bedrock-karatu-2025-capstone/assets-images

Step 3: Downloading Official Retail Store Images
📥 Downloading (wget)...
✅ Download complete (Size: 4.5M)

Step 4: Extracting Images
✅ Extraction complete
   Total images extracted: 47

Step 5: Uploading Images to S3
✅ Upload complete
   Total files in S3: 47

Step 7: Restarting Deployments
✅ Deployment restart commands issued

═══════════════════════════════════════════════════════════════════════════════
                         SETUP COMPLETE ✅
═══════════════════════════════════════════════════════════════════════════════

Summary:
  📁 Local images:     /home/WORKSPACE/.../assets-images (47 files)
  ☁️  S3 bucket:        s3://bedrock-assets-alt-soe-025-3359/ (47 files)
  🎯 Deployments:      Restarted (ui, assets, rabbitmq)
```

**Note:** The `assets-images/` directory is automatically ignored by `.gitignore`, so it won't be committed to the repository. You can safely re-run this script to update images.

### Step 6b: Monitor Pod Recovery

After running the setup script or manual upload commands:

```bash
# 1. Monitor pod transitions to Ready state
kubectl get pods -n retail-app -l "app in (ui,rabbitmq,assets)" -w

# 2. Expected timeline:
# - 0-30s:  Pods show 0/1 Running (containers starting)
# - 30-60s: Pods reach 1/1 Ready (readiness probes pass)
# - 60s+:   Pods stable at 1/1 Running

# 3. Exit watch with Ctrl+C
```

### Step 6c: Verify ALB is Provisioned

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
aws logs tail /aws/eks/project-bedrock-cluster/containers --region us-east-1 --follow
# View EKS control plane logs (API, audit, etc.)
aws logs tail /aws/eks/project-bedrock-cluster/cluster --follow
```

## Phase 9: Test Serverless Extension (S3-Lambda)

```bash
cd terraform
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

For comprehensive troubleshooting guidance, see [TROUBLESHOOT.md](TROUBLESHOOT.md).

This document covers:
- Pods not starting / stuck in Pending
- Pods crashing (CrashLoopBackOff)
- Database connection errors
- ALB provisioning issues
- CloudWatch logs not appearing
- Lambda not triggering on S3 upload
- Image pull errors
- UI 503 errors (S3 assets missing)
- RabbitMQ pod recovery
- ALB health check failures
- Probe configuration verification

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
- **EC2 Nodes**: t3.small (750 hours/month free)
- **RDS**: 750 hours/month free (MySQL 8.0, PostgreSQL 16.3)
- **ALB**: Partial free tier (730 hours/month)
- **S3**: 5GB storage free
- **Lambda**: 1 million requests/month free
- **CloudWatch Logs**: 5GB ingestion free

⚠️ **Scaling caveat**: The Free Tier account may have limits preventing scaling beyond 6-8 small instances. If you need more capacity, upgrade to a paid account or request a limit increase from AWS Support.

A comprehensive code review has been completed. See [CODE_REVIEW.md](CODE_REVIEW.md) for full details.

### Critical Issues Fixed
1. ✅ **Secrets Manager Recovery Window** (0 → 7 days) - Prevents accidental permanent data loss
2. ✅ **EKS Public Access CIDR** (0.0.0.0/0 → configurable) - Restricts API endpoint access
3. ✅ **Missing Module Output** - Added kubernetes_namespace export for dependency resolution
4. ✅ **Hardcoded Region** (us-east-1 → variable) - Makes code portable across regions

### High-Severity Fixes
1. ✅ **AWS Account ID Hardcoding** - Now dynamic via Terraform
2. ✅ **RabbitMQ Default Credentials** - Now generated secure random password
3. ✅ **RDS Endpoints Hardcoding** - Now dynamic via Terraform
4. ✅ **Missing TLS Configuration** - Added HTTPS/TLS instructions for Ingress
5. ✅ **GitHub Actions Syntax Error** - Fixed `{{ vars }}` → `${{ vars }}`

### Recommended Production Changes
Before deploying to production, update `terraform.tfvars`:

```hcl
# Restrict EKS API to your IP for security
eks_public_access_cidrs = ["YOUR_IP/32"]

# Extend retention for compliance
db_recovery_window_in_days = 30  # 7 is minimum

# In modules/rds/main.tf, update:
# backup_retention_period = 7  # Currently 1 day
# skip_final_snapshot = false  # Currently true
```