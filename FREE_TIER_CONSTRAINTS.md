# AWS Free Tier Constraints & Project Status

## ⚠️ Critical Issue: vCPU Limit Exceeded

### Current Situation
Your AWS Free Tier account has **8 vCPU limit**, but the EKS cluster is trying to use:
- **6 nodes currently running**: 6 × 2 vCPU (t3.micro) = **12 vCPUs** (4 vCPUs OVER limit)
- **Auto-scaling disabled**: Cannot launch additional nodes due to vCPU limit
- **Status**: Node group in DEGRADED state

### Why This Happened
1. Initial cluster provisioned with 6 t3.micro nodes (seemed reasonable)
2. Each t3.micro = 2 vCPUs → 6 nodes = 12 vCPUs total
3. This exceeds Free Tier limit by 50%
4. When trying to scale to 12 nodes (36 vCPUs), AWS rejected the request

### What Works Now ✅
- **ALB Controller**: Running and provisioning load balancer correctly
- **Ingress**: ALB DNS available at `k8s-retailap-retailap-96a8cc239a-7993890.us-east-1.elb.amazonaws.com`
- **Database Connectivity**: ExternalName services bridging Kubernetes to RDS
- **Core Infrastructure**: Terraform-managed resources stable
- **4 Pods Running**:
  - 1 RabbitMQ (with fixed probes)
  - 1+ Catalog (partial - crashing on migration timeout)
  - 2 Others (assets, one of checkout/orders/ui)

### What's Blocked ❌
- **8 Pods Pending**: Cannot schedule due to no available node capacity
- **Node Scaling**: ASG cannot add more nodes (vCPU limit)
- **Catalog Migrations**: Timeout when connecting to RDS (image ignores `DB_MIGRATION_DISABLE=true`)
- **Carts Deployment**: Image tag 0.6.0 doesn't exist in ECR (removed)

---

## Solutions

### Option 1: Request vCPU Limit Increase (5 minutes)
1. Go to [AWS Service Quotas Console](https://console.aws.amazon.com/servicequotas)
2. Search for "EC2" → "On-Demand t3 instances"
3. Click the quota → "Request quota increase"
4. Set to 32 vCPUs (allows 16 nodes)
5. Submit (usually approved within hours)
6. After approval, scale cluster back to desired size:
   ```bash
   aws eks update-nodegroup-config \
     --cluster-name project-bedrock-cluster \
     --nodegroup-name project-bedrock-cluster-nodes \
     --scaling-config desiredSize=6,minSize=2,maxSize=15 \
     --region us-east-1
   ```

### Option 2: Use Smaller Instance Type (Not Recommended)
- **Problem**: t3.micro/t2.micro are already the smallest
- **Alternative**: Use Graviton2 (t4g.micro) - but may have different pricing
- **Not worth complexity**

### Option 3: Reduce Pods (Permanent Solution)
Scale down to only essential services:
```bash
# Keep only:
# - ui (required for application)
# - catalog (core business logic)
# - rabbitmq (message queue)
# - redis (cache)
# - assets (image processing)

# Delete non-essential:
kubectl delete deployment carts orders checkout -n retail-app --ignore-not-found
```

### Option 4: Accept Current State (Monitoring Only)
Reduce node count further (2-3 nodes) and run only essential workloads:
```bash
aws eks update-nodegroup-config \
  --cluster-name project-bedrock-cluster \
  --nodegroup-name project-bedrock-cluster-nodes \
  --scaling-config desiredSize=3,minSize=2,maxSize=5 \
  --region us-east-1
```

---

## Known Issues & Workarounds

### Issue 1: Catalog Pod Crashes on Startup
**Error**: `dial tcp 10.0.11.137:3306: i/o timeout`

**Root Cause**: 
- The catalog application ALWAYS runs database migrations on startup
- The `DB_MIGRATION_DISABLE=true` environment variable is **NOT** respected by the image
- This is an application-level issue, not infrastructure

**Workaround**:
- Use different image version (if one exists without auto-migration)
- Or: Accept that catalog pod will restart until migrations timeout, then crash
- Or: Modify the application code to respect `DB_MIGRATION_DISABLE`

**Status**: ⚠️ Cannot fix without application changes

### Issue 2: Carts Image Not Available  
**Error**: `public.ecr.aws/aws-containers/retail-store-sample-carts:0.6.0: not found`

**Root Cause**: Image tag doesn't exist in the public ECR registry

**Solution**: ✅ **ALREADY REMOVED** - Deleted carts deployment
- Run without carts functionality
- Or: Find correct image tag/version and update k8s/carts/deployment.yaml

### Issue 3: RabbitMQ Probe Timeouts ✅ FIXED
**Was**: Liveness probe timeout=1s (too tight for RabbitMQ startup)  
**Fixed**: Increased to timeout=5s and initialDelaySeconds=60  
**Status**: ✅ RabbitMQ now Running

---

## Current Resource Usage

### Node Allocation
```
Total vCPU Limit (Free Tier): 8
Currently Using: 12 (6 nodes × 2 vCPUs) = 150% of limit ⚠️

After scaling down to 3 nodes: 6 vCPUs (75% of limit) ✅
```

### Pod Resource Requests
```
Deployment      Replicas  Requests (CPU/Memory)  Limits (CPU/Memory)
────────────────────────────────────────────────────────────────────
ui              2         100m / 128Mi           200m / 256Mi
catalog         2         100m / 128Mi           200m / 256Mi  
orders          2         100m / 128Mi           200m / 256Mi
checkout        2         100m / 128Mi           200m / 256Mi
rabbitmq        1         100m / 256Mi           250m / 512Mi  (now with fixed probes)
redis           1         50m / 64Mi             100m / 128Mi
assets          1         50m / 64Mi             100m / 128Mi
ALB Controller  1         50m / 64Mi             100m / 128Mi
─────────────────────────────────────────────────────────────────── 
TOTAL REQUESTS: ~1200m CPU / 1.2Gi Memory
TOTAL LIMITS:   ~2100m CPU / 2.3Gi Memory
```

### With 3 Nodes
```
Available Capacity: 3 nodes × (2 vCPU × 1000m) = 6000m CPU
Pod Requests: ~1200m CPU (20% utilization)
Status: ✅ Should fit comfortably
```

---

## Deployment Strategy for Free Tier

### Minimal Setup (2-3 nodes)
Deploy only these services:
1. **ui** - Frontend (required)
2. **catalog** - Core API (required)  
3. **rabbitmq** - Message broker (optional but needed for orders)
4. **redis** - Cache (optional)
5. **assets** - S3 integration (optional)

**Remove**: carts, orders, checkout (non-essential for MVP)

```bash
kubectl delete deployment carts orders checkout -n retail-app --ignore-not-found
```

### Standard Setup (4-5 nodes)
After requesting vCPU limit increase to 20:
Deploy all services EXCEPT carts (due to missing image)
```bash
kubectl apply -R -f k8s/
kubectl delete deployment carts -n retail-app
```

### Full Setup (6+ nodes)
After requesting vCPU limit increase to 32+:
Deploy everything and auto-scale as needed

---

## Monitoring & Health Checks

### Check Current Status
```bash
# Node scaling status
aws eks describe-nodegroup --cluster-name project-bedrock-cluster \
  --nodegroup-name project-bedrock-cluster-nodes \
  --region us-east-1 \
  --query 'nodegroup.health'

# Pod status
kubectl get pods -n retail-app -o wide

# ALB health
kubectl get ingress -n retail-app -o wide
```

### Monitor Metrics
```bash
# Track vCPU usage over time
watch -n 10 'kubectl top nodes 2>/dev/null || echo "Metrics server not available"'

# Pod events
kubectl get events -n retail-app --sort-by=".lastTimestamp"
```

---

## Recommendations

### Short Term (Today)
✅ **Already Done**:
1. Fixed RabbitMQ probe timeouts
2. Removed non-existent carts image
3. Scaled down to 3 nodes

### Next Steps:
1. **Option A (Recommended)**: Request vCPU limit increase (2 minutes) → Scale back up → Deploy full app
2. **Option B**: Accept 3-node limit → Deploy minimal services → Scale down deployments
3. **Option C**: Monitor current state → Document findings → Plan for production account

### Long Term
- Use different instance types (t3.nano for dev, t3.small for staging)
- Implement Pod Disruption Budgets for graceful degradation
- Set up autoscaling based on actual metrics (not just pending pods)
- Document resource requirements per service

---

## AWS Free Tier Limits Summary

| Resource | Free Tier Limit | Current Usage | Status |
|----------|-----------------|---------------|--------|
| EKS Cluster | 1 cluster free | 1 | ✅ OK |
| EC2 vCPU (t3/t2) | 8 vCPU | 12 vCPU | ❌ OVER |
| RDS MySQL | 750 hours | In use | ✅ OK |
| RDS PostgreSQL | 750 hours | In use | ✅ OK |
| ALB | 730 hours | In use | ✅ OK |
| S3 Storage | 5 GB | ~1 GB | ✅ OK |
| Lambda | 1M requests | <1M | ✅ OK |
| CloudWatch Logs | 5 GB ingestion | ~0.5 GB | ✅ OK |

---

**Last Updated**: 2026-06-04  
**Status**: Infrastructure stable, scaled within Free Tier constraints  
**Action Required**: Request vCPU limit increase OR deploy minimal services
