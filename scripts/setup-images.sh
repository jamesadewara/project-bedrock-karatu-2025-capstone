#!/bin/bash

# Retail Store Sample App - Image Download & S3 Upload Script
# Purpose: Download official retail store product images and upload to S3 bucket
# Target: Populate S3 assets for retail-app deployment on EKS
# Usage: bash scripts/setup-images.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="${PROJECT_ROOT}/assets-images"
TEMP_ZIP="/tmp/sample-images.zip"
S3_BUCKET="bedrock-assets-alt-soe-025-3359"
AWS_REGION="us-east-1"
GITHUB_RELEASE="https://github.com/aws-containers/retail-store-sample-app/releases/download/v1.2.1/sample-images.zip"

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║       RETAIL STORE SAMPLE APP - IMAGE DOWNLOAD & S3 UPLOAD                 ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# STEP 1: Verify Prerequisites
# ============================================================================
echo "Step 1: Verifying Prerequisites"
echo "───────────────────────────────────────────────────────────────────────────────"

# Check AWS CLI
if ! command -v aws &>/dev/null; then
    echo "❌ ERROR: AWS CLI not installed"
    echo "   Install with: pip install awscli"
    exit 1
fi
echo "✅ AWS CLI installed"

# Check wget or curl
if command -v wget &>/dev/null; then
    DOWNLOADER="wget"
elif command -v curl &>/dev/null; then
    DOWNLOADER="curl"
else
    echo "❌ ERROR: Neither wget nor curl is installed"
    exit 1
fi
echo "✅ Download tool available: $DOWNLOADER"

# Check kubectl
if ! command -v kubectl &>/dev/null; then
    echo "❌ ERROR: kubectl not installed"
    exit 1
fi
echo "✅ kubectl installed"

# Verify AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ ERROR: AWS credentials not configured"
    echo "   Run: aws configure"
    exit 1
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✅ AWS Account ID: $ACCOUNT_ID"

# Verify S3 bucket access
if ! aws s3 ls "s3://${S3_BUCKET}/" --region "$AWS_REGION" &>/dev/null; then
    echo "❌ ERROR: Cannot access S3 bucket: s3://${S3_BUCKET}/"
    exit 1
fi
echo "✅ S3 bucket accessible: s3://${S3_BUCKET}/"

echo ""

# ============================================================================
# STEP 2: Create Local Assets Directory
# ============================================================================
echo "Step 2: Setting Up Local Assets Directory"
echo "───────────────────────────────────────────────────────────────────────────────"

if [ -d "$ASSETS_DIR" ]; then
    echo "  ℹ Assets directory already exists: $ASSETS_DIR"
    FILE_COUNT=$(find "$ASSETS_DIR" -type f | wc -l)
    echo "  ℹ Current files in directory: $FILE_COUNT"
else
    mkdir -p "$ASSETS_DIR"
    echo "✅ Created assets directory: $ASSETS_DIR"
fi

echo ""

# ============================================================================
# STEP 3: Download Official Images
# ============================================================================
echo "Step 3: Downloading Official Retail Store Images"
echo "───────────────────────────────────────────────────────────────────────────────"
echo "  Source: $GITHUB_RELEASE"
echo ""

# Download using wget or curl
if [ "$DOWNLOADER" = "wget" ]; then
    echo "📥 Downloading (wget)..."
    wget -q --show-progress "$GITHUB_RELEASE" -O "$TEMP_ZIP"
else
    echo "📥 Downloading (curl)..."
    curl -L --progress-bar "$GITHUB_RELEASE" -o "$TEMP_ZIP"
fi

if [ ! -f "$TEMP_ZIP" ]; then
    echo "❌ ERROR: Failed to download images"
    exit 1
fi

ZIP_SIZE=$(du -h "$TEMP_ZIP" | cut -f1)
echo "✅ Download complete (Size: $ZIP_SIZE)"
echo ""

# ============================================================================
# STEP 4: Extract Images
# ============================================================================
echo "Step 4: Extracting Images to $ASSETS_DIR"
echo "───────────────────────────────────────────────────────────────────────────────"

# Check if unzip is available
if ! command -v unzip &>/dev/null; then
    echo "❌ ERROR: unzip command not found"
    exit 1
fi

# Extract with progress indication
unzip -q "$TEMP_ZIP" -d "$ASSETS_DIR" && {
    echo "✅ Extraction complete"
} || {
    echo "❌ ERROR: Failed to extract images"
    exit 1
}

# Count extracted files
FILE_COUNT=$(find "$ASSETS_DIR" -type f | wc -l)
echo "   Total images extracted: $FILE_COUNT"
echo ""

# ============================================================================
# STEP 5: Upload to S3
# ============================================================================
echo "Step 5: Uploading Images to S3"
echo "───────────────────────────────────────────────────────────────────────────────"
echo "  Destination: s3://${S3_BUCKET}/"
echo ""

aws s3 sync "$ASSETS_DIR" "s3://${S3_BUCKET}/" \
    --region "$AWS_REGION" \
    --delete \
    --quiet

# Verify upload
UPLOADED_COUNT=$(aws s3 ls "s3://${S3_BUCKET}/" --recursive --region "$AWS_REGION" | wc -l)
echo "✅ Upload complete"
echo "   Total files in S3: $UPLOADED_COUNT"
echo ""

# ============================================================================
# STEP 6: Verify Kubernetes Connectivity
# ============================================================================
echo "Step 6: Verifying Kubernetes Connectivity"
echo "───────────────────────────────────────────────────────────────────────────────"

if ! kubectl cluster-info &>/dev/null; then
    echo "⚠️  WARNING: Cannot connect to Kubernetes cluster"
    echo "   Skipping deployment restart"
    echo "   Run the following manually to restart deployments:"
    echo ""
    echo "   kubectl rollout restart deployment ui assets rabbitmq -n retail-app"
    echo ""
    exit 0
fi

echo "✅ Connected to cluster"
echo ""

# ============================================================================
# STEP 7: Restart Deployments
# ============================================================================
echo "Step 7: Restarting Deployments to Use New Images"
echo "───────────────────────────────────────────────────────────────────────────────"

for deployment in ui assets rabbitmq; do
    echo "  ⟳ Restarting $deployment..."
    kubectl rollout restart deployment/"$deployment" -n retail-app 2>/dev/null || {
        echo "  ⚠️  Could not restart $deployment (may not exist yet)"
    }
done

echo "✅ Deployment restart commands issued"
echo ""

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                         SETUP COMPLETE ✅                                   ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  📁 Local images:     $ASSETS_DIR ($FILE_COUNT files)"
echo "  ☁️  S3 bucket:        s3://${S3_BUCKET}/ ($UPLOADED_COUNT files)"
echo "  🎯 Deployments:      Restarted (ui, assets, rabbitmq)"
echo ""
echo "Next Steps:"
echo "  1. Monitor pod status:"
echo "     kubectl get pods -n retail-app -l 'app in (ui,rabbitmq,assets)' -w"
echo ""
echo "  2. Verify ALB is ready (wait 2-3 minutes):"
echo "     kubectl get ingress retail-app -n retail-app"
echo ""
echo "  3. Access application:"
echo "     ALB_DNS=\$(kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "     echo \"Open in browser: http://\$ALB_DNS\""
echo ""

# Cleanup
rm -f "$TEMP_ZIP"
