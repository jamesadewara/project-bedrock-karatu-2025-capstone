# Project Bedrock - Troubleshooting Guide

This document contains comprehensive troubleshooting steps for common issues encountered during deployment and operation of Project Bedrock.

## Pods not starting / stuck in Pending
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

## Pods crashing (CrashLoopBackOff)
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

## Database connection errors (timeout)
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

## ALB not provisioning
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

## CloudWatch logs not appearing
```bash
# Verify CloudWatch Observability add-on pod
kubectl get pods -n amazon-cloudwatch

# Check CloudWatch add-on logs
kubectl logs -n amazon-cloudwatch -l app=cloudwatch-observability --tail=20

# Verify CloudWatch log groups were created
aws logs describe-log-groups --log-group-name-prefix "/aws/eks/project-bedrock-cluster"
```

## Lambda not triggering on S3 upload
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

## Carts ImagePullBackOff - Image not found
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

## UI returning 503 Service Temporarily Unavailable (S3 Assets Missing)

**Root Cause:** The S3 bucket used for assets is empty. The assets service has no product images to serve, causing the UI to return 503 errors to clients.

**Symptoms:**
- ALB responds with 503 to all requests
- `assets` pod may show 1/1 Ready but UI cannot reach it
- UI and RabbitMQ pods stuck at 0/1 with readiness probe failures
- Ingress health check showing targets as unhealthy

**Solution:** Use the `setup-images.sh` script from Phase 6 of the RUNBOOK:

```bash
bash scripts/setup-images.sh
```

This script will:
1. ✅ Download official retail store images from GitHub
2. ✅ Extract and upload them to your S3 bucket
3. ✅ Restart ui, rabbitmq, and assets deployments
4. ✅ Monitor pods transitioning to 1/1 Ready

**Troubleshooting if pods still don't come ready:**

```bash
# Check assets pod logs
kubectl logs -n retail-app -l app=assets --tail=50

# Check UI pod logs (may show connection errors to assets)
kubectl logs -n retail-app -l app=ui --tail=50

# Check readiness probe status
kubectl describe pod -n retail-app -l app=ui | grep -A 20 "Readiness probe"

# If bucket still empty, check with (run this inside the terraform/ directory):
BUCKET_NAME=$(terraform output -raw assets_bucket_name)
aws s3 ls s3://${BUCKET_NAME}/ --recursive --summarize

# If sync permissions denied, ensure AWS credentials have s3:* permissions:
aws iam get-user-policy --user-name $(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f6) \
  --policy-name POLICY_NAME
```

## RabbitMQ Pods Stuck at 0/1 Ready

**Root Cause:** Readiness probe failing because of missing connection to assets service or broker startup issues.

**Symptoms:**
- `rabbitmq` pod shows `0/1 Running` with high restart count
- Events show readiness probe failed repeatedly
- Pod logs show connection timeouts or AMQP errors

**Quick Fix:**

```bash
# 1. Check if assets sync completed (run this inside the terraform/ directory)
BUCKET_NAME=$(terraform output -raw assets_bucket_name)
aws s3 ls s3://${BUCKET_NAME}/ --recursive | wc -l

# 2. Delete and restart RabbitMQ pod
kubectl delete pod -n retail-app -l app=rabbitmq
kubectl rollout restart deployment/rabbitmq -n retail-app

# 3. Monitor recovery
kubectl get pods -n retail-app -l app=rabbitmq -w

# 4. Check pod logs for startup errors
kubectl logs -n retail-app -l app=rabbitmq --tail=100

# 5. If still failing, check RabbitMQ specific errors:
kubectl exec -it $(kubectl get pods -n retail-app -l app=rabbitmq -o jsonpath='{.items[0].metadata.name}') \
  -n retail-app -- rabbitmq-diagnostics status
```

## ALB Health Check Failing (Targets Unhealthy)

**Symptoms:**
- Ingress shows ALB DNS, but targets marked as unhealthy
- 503 Service Unavailable from client browsers
- `kubectl get endpoints ui` shows no ready addresses

**Diagnosis & Recovery:**

```bash
# 1. Check pod readiness (local Kubernetes perspective)
kubectl get pods -n retail-app -o wide | grep ui

# 2. Check service endpoints (should show ready pod IPs)
kubectl get endpoints ui -n retail-app

# 3. Get ALB Target Group ARN
ALB_DNS=$(kubectl get ingress retail-app -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(DNSName, '$ALB_DNS')].LoadBalancerArn" \
  --output text)

# 4. Get Target Group
TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn $ALB_ARN \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# 5. Check target health
aws elbv2 describe-target-health --target-group-arn $TG_ARN

# 6. If targets unhealthy, restart pods
kubectl rollout restart deployment/ui -n retail-app
kubectl rollout restart deployment/assets -n retail-app

# 7. Wait for pod transitions and recheck target health
sleep 30
aws elbv2 describe-target-health --target-group-arn $TG_ARN
```

## Probe Configuration Verification

To verify that all probe configurations are correct per service type requirements:

```bash
# Check Spring Boot Actuator paths (UI, Orders, Carts)
for app in ui orders carts; do
  echo "=== $app ==="
  kubectl get deployment $app -n retail-app -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}'
  echo ""
done

# Check Go native paths (Catalog, Checkout)
for app in catalog checkout; do
  echo "=== $app ==="
  kubectl get deployment $app -n retail-app -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}'
  echo ""
done

# Check Go static file endpoint (Assets)
echo "=== assets ==="
kubectl get deployment assets -n retail-app -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}'
echo ""

# Expected results:
# ui: /actuator/health (Spring Boot)
# orders: /actuator/health (Spring Boot)
# carts: /actuator/health (Spring Boot)
# catalog: /health (Go native)
# checkout: /health (Node.js native)
# assets: /health.html (Go static file server)
```

---

**For deployment procedures, see [RUNBOOK.md](RUNBOOK.md)**
