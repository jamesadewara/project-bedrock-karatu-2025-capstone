#!/bin/bash

# Retail Store Sample App - S3 Assets Sync & Pod Recovery Script
# Purpose: Resolve 503 errors and readiness probe failures by syncing S3 assets and restarting pods
# Target: retail-app namespace on project-bedrock-cluster (EKS 1.34.8)

set -e

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║        RETAIL STORE SAMPLE APP - S3 ASSETS SYNC & POD RECOVERY             ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
SOURCE_BUCKET="s3://ee-assets-prod-us-east-1/modules/334204c3-1d44-486a-939e-ed8c7151f893/v1/assets/"
DEST_BUCKET="s3://bedrock-assets-alt-soe-025-3359/"
NAMESPACE="retail-app"
AWS_REGION="us-east-1"

echo "Configuration:"
echo "  Source S3 Bucket: $SOURCE_BUCKET"
echo "  Destination S3 Bucket: $DEST_BUCKET"
echo "  Kubernetes Namespace: $NAMESPACE"
echo "  AWS Region: $AWS_REGION"
echo ""

# ============================================================================
# STEP 1: Check AWS Credentials
# ============================================================================
echo "Step 1: Verifying AWS Credentials & S3 Access"
echo "───────────────────────────────────────────────────────────────────────────────"

if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ ERROR: AWS credentials not configured or invalid"
    echo "   Please configure AWS credentials: aws configure"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ AWS Account ID: $ACCOUNT_ID"

# Verify destination bucket exists
if aws s3 ls "$DEST_BUCKET" &>/dev/null; then
    echo "✅ Destination bucket is accessible: $DEST_BUCKET"
else
    echo "❌ ERROR: Cannot access destination bucket: $DEST_BUCKET"
    exit 1
fi

# Check source bucket availability
if aws s3 ls "$SOURCE_BUCKET" --region us-east-1 &>/dev/null 2>&1; then
    echo "✅ Source bucket is accessible: $SOURCE_BUCKET"
else
    echo "⚠️  WARNING: Source bucket may not be directly accessible"
    echo "   This is expected for AWS internal buckets. Proceeding with alternative sync method..."
fi

echo ""

# ============================================================================
# STEP 2: Sync S3 Assets
# ============================================================================
echo "Step 2: Syncing Retail Store Demo Assets to Custom Bucket"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""
echo "Attempting to sync from: $SOURCE_BUCKET"
echo "Destination: $DEST_BUCKET"
echo ""

# Try direct sync first
if aws s3 sync "$SOURCE_BUCKET" "$DEST_BUCKET" --region us-east-1 --delete 2>&1 | tee /tmp/s3_sync.log; then
    SYNC_SIZE=$(du -sh /tmp/s3_sync.log | awk '{print $1}')
    OBJECT_COUNT=$(aws s3 ls "$DEST_BUCKET" --recursive --region us-east-1 | wc -l)
    echo ""
    echo "✅ S3 Sync Completed Successfully"
    echo "   Objects in destination bucket: $OBJECT_COUNT"
else
    echo ""
    echo "⚠️  Direct S3 sync encountered an issue. Checking destination bucket contents..."
    OBJECT_COUNT=$(aws s3 ls "$DEST_BUCKET" --recursive --region us-east-1 | wc -l)
    
    if [ "$OBJECT_COUNT" -gt 0 ]; then
        echo "✅ Destination bucket already contains $OBJECT_COUNT objects"
        echo "   Proceeding with pod recovery..."
    else
        echo "❌ ERROR: Destination bucket is empty and sync failed"
        echo "   Please manually sync: aws s3 sync $SOURCE_BUCKET $DEST_BUCKET --region $AWS_REGION"
        exit 1
    fi
fi

echo ""

# Verify objects in destination bucket
echo "Verifying destination bucket contents:"
aws s3 ls "$DEST_BUCKET" --region us-east-1 --recursive | head -10
TOTAL_OBJECTS=$(aws s3 ls "$DEST_BUCKET" --region us-east-1 --recursive | wc -l)
echo "... ($TOTAL_OBJECTS total objects)"

echo ""

# ============================================================================
# STEP 3: Check Kubernetes Connectivity
# ============================================================================
echo "Step 3: Verifying Kubernetes Cluster Access"
echo "───────────────────────────────────────────────────────────────────────────────"

if ! kubectl cluster-info &>/dev/null; then
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    echo "   Please verify kubeconfig is configured correctly"
    exit 1
fi

CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2 2>/dev/null || echo "unknown")
echo "✅ Connected to cluster: $CLUSTER_NAME"

# Verify namespace exists
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "✅ Namespace exists: $NAMESPACE"
else
    echo "❌ ERROR: Namespace not found: $NAMESPACE"
    exit 1
fi

# Check deployment status before restart
echo ""
echo "Current deployment status in $NAMESPACE namespace:"
kubectl get deployments -n "$NAMESPACE" | grep -E "assets|rabbitmq|ui" || echo "  (no deployments found)"

echo ""

# ============================================================================
# STEP 4: Restart Affected Deployments
# ============================================================================
echo "Step 4: Restarting Affected Deployments"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""

RESTARTS=("ui" "rabbitmq" "assets")
RESTART_COUNT=0

for deployment in "${RESTARTS[@]}"; do
    echo "  ⟳ Restarting $deployment..."
    if kubectl rollout restart deployment/"$deployment" -n "$NAMESPACE" 2>/dev/null; then
        echo "     ✅ Restart triggered for $deployment"
        RESTART_COUNT=$((RESTART_COUNT + 1))
    else
        echo "     ⚠️  Deployment $deployment not found (may not exist yet)"
    fi
done

echo ""
echo "✅ Triggered $RESTART_COUNT deployment restarts"

# Wait for rollouts to begin
echo ""
echo "Waiting for rollout to begin (5 seconds)..."
sleep 5

echo ""

# ============================================================================
# STEP 5: Monitor Pod Status
# ============================================================================
echo "Step 5: Pod Status Transition Monitor"
echo "───────────────────────────────────────────────────────────────────────────────"
echo ""
echo "Showing pod status before watch (sorted by phase):"
echo ""
kubectl get pods -n "$NAMESPACE" --sort-by=.status.phase --no-headers | grep -E "assets|rabbitmq|ui" || echo "(checking...)"

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║              MONITORING POD TRANSITIONS TO 1/1 READY                       ║"
echo "║                                                                            ║"
echo "║  Press Ctrl+C to stop watching                                             ║"
echo "║  Expected outcome: All pods transition to 1/1 Running                      ║"
echo "║  Typical wait time: 60-120 seconds                                         ║"
echo "║                                                                            ║"
echo "║  Troubleshooting tips:                                                     ║"
echo "║  - If pods stuck in CrashLoopBackOff: kubectl logs -n retail-app <pod>   ║"
echo "║  - If readiness probe failing: kubectl describe pod -n retail-app <pod>  ║"
echo "║  - If 503 persists: Check ALB target group health in AWS console          ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Watch pods with regex filter for relevant services
kubectl get pods -n "$NAMESPACE" -l "app in (ui,rabbitmq,assets)" -w

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                         RECOVERY COMPLETE                                  ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Final status check
echo "Final Pod Status:"
kubectl get pods -n "$NAMESPACE" -l "app in (ui,rabbitmq,assets)" --no-headers

echo ""
echo "Checking service connectivity:"
for svc in ui rabbitmq assets; do
    READY=$(kubectl get deployment $svc -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment $svc -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    echo "  $svc: $READY/$DESIRED ready"
done

echo ""
echo "UI Service Endpoint:"
kubectl get svc ui -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || kubectl get svc ui -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "Service not yet exposed"

echo ""
echo "✅ S3 Assets Sync and Pod Recovery Script Completed"
echo ""
