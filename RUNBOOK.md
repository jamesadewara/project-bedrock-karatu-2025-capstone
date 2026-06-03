# Project Bedrock - Operational Runbook

**InnovateMart EKS Deployment - Runbook for Operations Team**

## Table of Contents
1. [Daily Operations](#daily-operations)
2. [Deployment Procedures](#deployment-procedures)
3. [Monitoring & Alerting](#monitoring--alerting)
4. [Incident Response](#incident-response)
5. [Security Operations](#security-operations)
6. [Backup & Recovery](#backup--recovery)
7. [Scaling Procedures](#scaling-procedures)
8. [Cost Optimization](#cost-optimization)
9. [Troubleshooting Guides](#troubleshooting-guides)
10. [Maintenance Windows](#maintenance-windows)
11. [Namecheap DNS + CNAME Setup](#namecheap-dns--cname-setup)
12. [ACM Certificate Validation](#acm-certificate-validation)

---

## Namecheap DNS + CNAME Setup

### Architecture

```
User Browser
    ↓
DNS Query → Namecheap DNS (your nameservers)
    ↓
CNAME Record: www.yourdomain.com → ALB DNS
    ↓
AWS ALB (Application Load Balancer)
    ↓
EKS Pods (retail-app namespace)
```

### Why This Approach?

| Approach | Complexity | Cost | Control |
|---|---|---|---|
| Route 53 nameserver delegation | Medium | $0.50/month | AWS manages DNS |
| **Namecheap CNAME (this guide)** | **Low** | **$0** | **You manage DNS in Namecheap** |

**Benefits:**
- No Route 53 hosted zone needed ($0.50/month saved)
- Keep Namecheap as your DNS provider
- Simple CNAME record pointing to ALB
- ACM certificate validation via DNS (manual CNAME records)

---

## ACM Certificate Validation with Namecheap

### Step 1: Terraform Creates ACM Certificate

After `terraform apply`, get the validation records:

```bash
terraform output acm_validation_cname_records
```

Output example:
```json
[
  {
    "name" = "_c1705d84de99d59858171de92e29f074.spatialdesign3d.site.",
    "type" = "CNAME",
    "value" = "_f2010e272918efff4812418b3e2b38e2.jkddzztszm.acm-validations.aws."
  }
]
```

### Step 2: Add ACM Validation CNAME in Namecheap

1. Log into [Namecheap Dashboard](https://ap.www.namecheap.com/)
2. Go to **Domain List** → Click **Manage** next to your domain
3. Click the **Advanced DNS** tab
4. In the **Host Records** section, click **ADD NEW RECORD**

| Field | Value |
|---|---|
| **Type** | CNAME Record |
| **Host** | `_c1705d84de99d59858171de92e29f074` (the part before your domain) |
| **Value** | `_f2010e272918efff4812418b3e2b38e2.jkddzztszm.acm-validations.aws.` |
| **TTL** | 5 minutes |

5. Click **Save All Changes**

**Note:** The host field is the subdomain part only. If the full name is `_abc123.yourdomain.com.`, enter just `_abc123`.

### Step 3: Wait for ACM Validation

```bash
# Check certificate status
aws acm describe-certificate   --certificate-arn $(terraform output -raw acm_certificate_arn)   --region us-east-1   --query 'Certificate.Status'

# Should change from PENDING_VALIDATION to ISSUED
# This takes 5-30 minutes
```

### Step 4: Add ALB CNAME Record in Namecheap

After Helm deploys the app and creates the ALB:

```bash
# Get ALB DNS name
kubectl get ingress -n retail-app   -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# Output example:
# k8s-retailapp-ui-1234567890.us-east-1.elb.amazonaws.com
```

In Namecheap:

| Field | Value |
|---|---|
| **Type** | CNAME Record |
| **Host** | `www` (or `bedrock` for subdomain) |
| **Value** | `k8s-retailapp-ui-1234567890.us-east-1.elb.amazonaws.com` |
| **TTL** | 5 minutes |

### Step 5: For Root Domain (@)

If you want `yourdomain.com` (without `www`):

**Option A: URL Redirect (Recommended)**
- Type: URL Redirect Record
- Host: `@`
- Value: `http://www.yourdomain.com`
- Unmasked redirect

**Option B: ALIAS Record (if Namecheap supports it)**
- Type: ALIAS Record
- Host: `@`
- Value: ALB DNS name

**Note:** CNAME cannot be used for root domain (`@`) according to DNS standards.

### Step 6: Verify DNS Propagation

```bash
# Check CNAME resolution
dig CNAME www.yourdomain.com

# Should show:
# www.yourdomain.com.  CNAME  k8s-retailapp-ui-1234567890.us-east-1.elb.amazonaws.com.

# Check propagation
https://www.whatsmydns.net/
# Enter: www.yourdomain.com
# Select: CNAME
```

### Step 7: Test Your Application

```bash
# Test HTTP
curl -I http://www.yourdomain.com

# Should return HTTP 200
# If you see 404, the ALB might not be fully ready yet

# Open in browser
http://www.yourdomain.com
```

---

## Daily Operations

### Morning Health Check (Run at 9:00 AM WAT)

```bash
# 1. Check cluster status
aws eks describe-cluster --name project-bedrock-cluster --region us-east-1

# 2. Check node status
kubectl get nodes

# 3. Check all pods in retail-app namespace
kubectl get pods -n retail-app -o wide

# 4. Check pod resource usage
kubectl top pods -n retail-app

# 5. Check ingress status
kubectl get ingress -n retail-app

# 6. Check ALB target health
aws elbv2 describe-target-health   --target-group-arn $(aws elbv2 describe-target-groups     --names retail-app-ui --query 'TargetGroups[0].TargetGroupArn' --output text)   --region us-east-1

# 7. Check RDS status
aws rds describe-db-instances   --db-instance-identifier project-bedrock-cluster-catalog   --region us-east-1   --query 'DBInstances[0].DBInstanceStatus'

aws rds describe-db-instances   --db-instance-identifier project-bedrock-cluster-orders   --region us-east-1   --query 'DBInstances[0].DBInstanceStatus'

# 8. Check CloudWatch logs for errors
aws logs filter-log-events   --log-group-name /aws/containerinsights/project-bedrock-cluster/application   --filter-pattern "ERROR"   --region us-east-1   --start-time $(date -d '1 hour ago' +%s)000
```

### Evening Check (Run at 6:00 PM WAT)

```bash
# 1. Verify all pods are healthy
kubectl get pods -n retail-app

# 2. Check for any restart loops
kubectl get pods -n retail-app -o json | jq '.items[] | select(.status.containerStatuses[0].restartCount > 0) | .metadata.name'

# 3. Check S3 bucket for new uploads
aws s3 ls s3://bedrock-assets-jamesadewara/uploads/ --recursive | tail -20

# 4. Check Lambda invocations
aws logs filter-log-events   --log-group-name /aws/lambda/bedrock-asset-processor   --region us-east-1   --start-time $(date -d '1 hour ago' +%s)000
```

---

## Deployment Procedures

### Standard Application Deployment

**Pre-requisites:**
- PR approved and merged to main
- Terraform plan reviewed
- Helm values validated

**Procedure:**

```bash
# 1. Verify pipeline status
cd /path/to/repo
gh run list --workflow="Terraform Apply"

# 2. If manual deployment needed:
# Update kubeconfig
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1

# 3. Update Helm dependencies
cd helm
helm dependency update

# 4. Deploy with Helm
helm upgrade --install retail-app .   --namespace retail-app   --values values.yaml   --wait   --timeout 10m

# 5. Verify deployment
kubectl get pods -n retail-app
kubectl rollout status deployment/ui -n retail-app
kubectl rollout status deployment/catalog -n retail-app
kubectl rollout status deployment/carts -n retail-app
kubectl rollout status deployment/orders -n retail-app
kubectl rollout status deployment/checkout -n retail-app

# 6. Verify ingress
kubectl get ingress -n retail-app

# 7. Test application
curl -s http://$(kubectl get ingress -n retail-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')/health
```

### Infrastructure Deployment (Terraform)

**For manual deployment (not recommended - use CI/CD):**

```bash
cd terraform

# 1. Initialize
terraform init

# 2. Plan and review
terraform plan -out=tfplan

# 3. Apply (requires approval)
terraform apply tfplan

# 4. Generate grading.json
terraform output -json > ../grading.json
```

### Rollback Procedure

**Application Rollback:**

```bash
# Rollback to previous Helm revision
helm rollback retail-app -n retail-app

# Or rollback specific deployment
kubectl rollout undo deployment/ui -n retail-app
```

**Infrastructure Rollback:**

```bash
# If using Terraform state versioning
cd terraform
terraform init

# List previous states
terraform state list

# Restore from backup (if available)
# Or manually revert changes in git and re-apply
```

---

## Monitoring & Alerting

### CloudWatch Dashboards

**Create a custom dashboard:**

```bash
aws cloudwatch put-dashboard   --dashboard-name project-bedrock-cluster   --dashboard-body file://docs/dashboard.json   --region us-east-1
```

**Key Metrics to Monitor:**

| Metric | Namespace | Threshold | Action |
|---|---|---|---|
| CPU Utilization | AWS/EC2 | > 80% for 5 min | Scale nodes |
| Memory Utilization | ContainerInsights | > 85% for 5 min | Scale pods |
| Pod Restarts | ContainerInsights | > 3 in 10 min | Investigate |
| ALB 5xx Errors | AWS/ApplicationELB | > 10 in 5 min | Check app logs |
| RDS CPU | AWS/RDS | > 80% for 10 min | Scale DB or optimize |
| RDS Storage | AWS/RDS | > 85% | Expand storage |
| Lambda Errors | AWS/Lambda | > 5 in 5 min | Check function logs |
| Lambda Duration | AWS/Lambda | > 20s | Optimize function |

### CloudWatch Alarms

**Set up critical alarms:**

```bash
# High CPU on EKS nodes
aws cloudwatch put-metric-alarm   --alarm-name bedrock-eks-high-cpu   --alarm-description "EKS nodes CPU > 80%"   --metric-name CPUUtilization   --namespace AWS/EC2   --statistic Average   --period 300   --threshold 80   --comparison-operator GreaterThanThreshold   --evaluation-periods 2   --alarm-actions arn:aws:sns:us-east-1:ACCOUNT_ID:bedrock-alerts   --region us-east-1

# RDS storage low
aws cloudwatch put-metric-alarm   --alarm-name bedrock-rds-storage-low   --alarm-description "RDS storage < 20% free"   --metric-name FreeStorageSpace   --namespace AWS/RDS   --statistic Average   --period 300   --threshold 2147483648   --comparison-operator LessThanThreshold   --evaluation-periods 1   --alarm-actions arn:aws:sns:us-east-1:ACCOUNT_ID:bedrock-alerts   --region us-east-1
```

---

## Incident Response

### P1 - Application Down

**Symptoms:** ALB returning 502/503, no healthy targets

**Response:**

```bash
# 1. Check pod status immediately
kubectl get pods -n retail-app
kubectl describe pods -n retail-app

# 2. Check pod logs
kubectl logs -n retail-app -l app=ui --tail=100
kubectl logs -n retail-app -l app=catalog --tail=100

# 3. Check if nodes are healthy
kubectl get nodes
kubectl describe nodes

# 4. Check events
kubectl get events -n retail-app --sort-by='.lastTimestamp' | tail -20

# 5. If pods are crashing, check resource limits
kubectl top pods -n retail-app

# 6. If needed, restart deployments
kubectl rollout restart deployment/ui -n retail-app
kubectl rollout restart deployment/catalog -n retail-app
kubectl rollout restart deployment/carts -n retail-app
kubectl rollout restart deployment/orders -n retail-app
kubectl rollout restart deployment/checkout -n retail-app
```

### P2 - Database Connection Issues

**Symptoms:** Application pods showing DB connection errors

**Response:**

```bash
# 1. Check RDS status
aws rds describe-db-instances   --db-instance-identifier project-bedrock-cluster-catalog   --region us-east-1

# 2. Check security group rules
aws ec2 describe-security-groups   --group-ids $(terraform output -raw rds_security_group_id)   --region us-east-1

# 3. Verify secrets exist
kubectl get secrets -n retail-app
kubectl describe secret catalog-db-credentials -n retail-app

# 4. Test connectivity from a pod
kubectl run debug --rm -i --tty --image=mysql:8.0 --restart=Never --   mysql -h $(terraform output -raw catalog_db_endpoint) -u admin -p

# 5. Check RDS logs
aws rds describe-db-log-files   --db-instance-identifier project-bedrock-cluster-catalog   --region us-east-1
```

### P3 - High Latency

**Symptoms:** Slow response times, ALB latency metrics high

**Response:**

```bash
# 1. Check resource usage
kubectl top pods -n retail-app
kubectl top nodes

# 2. Check HPA status (if configured)
kubectl get hpa -n retail-app

# 3. Scale up if needed
kubectl scale deployment ui --replicas=4 -n retail-app
kubectl scale deployment catalog --replicas=4 -n retail-app

# 4. Check ALB metrics
aws cloudwatch get-metric-statistics   --namespace AWS/ApplicationELB   --metric-name TargetResponseTime   --dimensions Name=LoadBalancer,Value=$(aws elbv2 describe-load-balancers --names retail-app --query 'LoadBalancers[0].LoadBalancerArn' --output text | cut -d'/' -f3)   --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)   --end-time $(date -u +%Y-%m-%dT%H:%M:%S)   --period 300   --statistics Average   --region us-east-1
```

### P4 - Lambda Failures

**Symptoms:** S3 uploads not triggering Lambda, CloudWatch errors

**Response:**

```bash
# 1. Check Lambda function status
aws lambda get-function --function-name bedrock-asset-processor --region us-east-1

# 2. Check CloudWatch logs
aws logs tail /aws/lambda/bedrock-asset-processor --follow --region us-east-1

# 3. Check S3 event notification
aws s3api get-bucket-notification-configuration   --bucket bedrock-assets-jamesadewara   --region us-east-1

# 4. Verify Lambda permissions
aws lambda get-policy --function-name bedrock-asset-processor --region us-east-1

# 5. If needed, re-invoke manually for testing
aws lambda invoke   --function-name bedrock-asset-processor   --payload '{"Records":[{"s3":{"bucket":{"name":"bedrock-assets-jamesadewara"},"object":{"key":"test.jpg"}}}]}'   --region us-east-1   response.json
```

---

## Security Operations

### Rotate Developer Credentials

**Monthly rotation for bedrock-dev-view:**

```bash
# 1. Create new access key
aws iam create-access-key --user-name bedrock-dev-view --region us-east-1

# 2. Update applications with new key
# 3. Verify new key works
# 4. Deactivate old key
aws iam update-access-key --user-name bedrock-dev-view --access-key-id OLD_KEY --status Inactive --region us-east-1

# 5. Delete old key after 24 hours
aws iam delete-access-key --user-name bedrock-dev-view --access-key-id OLD_KEY --region us-east-1
```

### Audit Kubernetes Access

```bash
# Check who has access to the cluster
kubectl get clusterrolebindings
kubectl get rolebindings -n retail-app

# Check dev user permissions
kubectl auth can-i --list --as bedrock-dev-view -n retail-app

# Verify dev user cannot delete
kubectl auth can-i delete pods --as bedrock-dev-view -n retail-app
# Expected: no
```

### Review Security Groups

```bash
# Monthly review
aws ec2 describe-security-groups   --filters Name=tag:Project,Values=karatu-2025-capstone   --region us-east-1
```

---

## Backup & Recovery

### RDS Backup Strategy

**Automated Backups:**
- Daily automated backups (retention: 1 day as configured)
- Manual snapshots before major changes

**Create Manual Snapshot:**

```bash
aws rds create-db-snapshot   --db-instance-identifier project-bedrock-cluster-catalog   --db-snapshot-identifier catalog-$(date +%Y%m%d-%H%M%S)   --region us-east-1

aws rds create-db-snapshot   --db-instance-identifier project-bedrock-cluster-orders   --db-snapshot-identifier orders-$(date +%Y%m%d-%H%M%S)   --region us-east-1
```

**Restore from Snapshot:**

```bash
aws rds restore-db-instance-from-db-snapshot   --db-instance-identifier project-bedrock-cluster-catalog-restored   --db-snapshot-identifier SNAPSHOT_ID   --region us-east-1
```

### DynamoDB Backup

**Enable Point-in-Time Recovery:** Already enabled in Terraform

**Create On-Demand Backup:**

```bash
aws dynamodb create-backup   --table-name bedrock-carts   --backup-name bedrock-carts-$(date +%Y%m%d)   --region us-east-1
```

### S3 Backup

**Versioning:** Not enabled (as per exam requirements)

**Manual Backup:**

```bash
aws s3 sync s3://bedrock-assets-jamesadewara s3://bedrock-assets-jamesadewara-backup-$(date +%Y%m%d)
```

---

## Scaling Procedures

### Horizontal Pod Autoscaling (HPA)

**Apply HPA manifests:**

```bash
# Create HPA for UI
kubectl autoscale deployment ui   --cpu-percent=70   --min=2   --max=10   -n retail-app

# Create HPA for Catalog
kubectl autoscale deployment catalog   --cpu-percent=70   --min=2   --max=10   -n retail-app

# Verify
kubectl get hpa -n retail-app
```

### Vertical Node Scaling

**Scale EKS node group:**

```bash
# Scale up
aws eks update-nodegroup-config   --cluster-name project-bedrock-cluster   --nodegroup-name project-bedrock-cluster-nodes   --scaling-config minSize=2,maxSize=5,desiredSize=3   --region us-east-1

# Scale down (for cost saving)
aws eks update-nodegroup-config   --cluster-name project-bedrock-cluster   --nodegroup-name project-bedrock-cluster-nodes   --scaling-config minSize=0,maxSize=3,desiredSize=0   --region us-east-1
```

### RDS Scaling

**Scale instance class:**

```bash
aws rds modify-db-instance   --db-instance-identifier project-bedrock-cluster-catalog   --db-instance-class db.t3.small   --apply-immediately   --region us-east-1
```

**Scale storage:**

```bash
aws rds modify-db-instance   --db-instance-identifier project-bedrock-cluster-catalog   --allocated-storage 30   --apply-immediately   --region us-east-1
```

---

## Cost Optimization

### Daily Cost Check

```bash
# Get current month costs
aws ce get-cost-and-usage   --time-period Start=$(date +%Y-%m-01),End=$(date -d "+1 month" +%Y-%m-01)   --granularity DAILY   --metrics BlendedCost   --group-by Type=DIMENSION,Key=SERVICE   --region us-east-1
```

### Cost-Saving Measures

**1. Scale down when not working:**

```bash
# Scale EKS nodes to 0
aws eks update-nodegroup-config   --cluster-name project-bedrock-cluster   --nodegroup-name project-bedrock-cluster-nodes   --scaling-config desiredSize=0,minSize=0,maxSize=3   --region us-east-1

# Stop RDS instances (if allowed by exam requirements)
aws rds stop-db-instance   --db-instance-identifier project-bedrock-cluster-catalog   --region us-east-1

aws rds stop-db-instance   --db-instance-identifier project-bedrock-cluster-orders   --region us-east-1
```

**2. Delete ALB when not needed:**

```bash
# Delete ingress (removes ALB)
kubectl delete ingress -n retail-app retail-app-ui
```

**3. Destroy entire stack (after grading):**

```bash
cd terraform
terraform destroy -auto-approve
```

---

## Troubleshooting Guides

### Terraform Issues

**State Lock:**
```bash
# Find lock ID
terraform force-unlock <LOCK_ID>

# Or remove lock from S3
aws s3 rm s3://karatu-terraform-state-jamesadewara/project-bedrock/terraform.tfstate.lock.info
```

**Provider Errors:**
```bash
# Reinitialize
terraform init -upgrade

# Clear plugin cache
rm -rf .terraform/
terraform init
```

### Helm Issues

**Chart Not Found:**
```bash
# Update repositories
helm repo update

# Login to ECR Public
aws ecr-public get-login-password --region us-east-1 | helm registry login public.ecr.aws --username AWS --password-stdin
```

**Release Failed:**
```bash
# Check status
helm status retail-app -n retail-app

# Get history
helm history retail-app -n retail-app

# Rollback
helm rollback retail-app <REVISION> -n retail-app
```

### Kubernetes Issues

**Pod Stuck Pending:**
```bash
# Check events
kubectl describe pod <pod-name> -n retail-app

# Common causes:
# - Insufficient resources: Scale nodes
# - Image pull errors: Check ECR access
# - PVC issues: Check storage class
```

**ImagePullBackOff:**
```bash
# Check image availability
kubectl describe pod <pod-name> -n retail-app | grep -A 5 "Events"

# Verify node IAM role has ECR access
aws iam list-attached-role-policies --role-name project-bedrock-cluster-node-group-role
```

### ALB Issues

**ALB Not Created:**
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check ingress annotations
kubectl get ingress -n retail-app -o yaml

# Verify subnets are tagged
aws ec2 describe-subnets   --filters "Name=tag:kubernetes.io/role/elb,Values=1"   --region us-east-1
```

**ALB 502 Errors:**
```bash
# Check target health
aws elbv2 describe-target-health   --target-group-arn $(aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, `retail-app`)].TargetGroupArn' --output text)   --region us-east-1

# Check pod readiness probes
kubectl describe pod <pod-name> -n retail-app
```

### Namecheap DNS Issues

**CNAME Not Working:**
```bash
# Check CNAME resolution
dig CNAME www.yourdomain.com

# Should show:
# www.yourdomain.com.  CNAME  k8s-retailapp-ui-1234567890.us-east-1.elb.amazonaws.com.

# If not showing, wait longer or check Namecheap configuration
```

**ACM Validation Failing:**
```bash
# Check certificate status
aws acm describe-certificate   --certificate-arn $(terraform output -raw acm_certificate_arn)   --region us-east-1   --query 'Certificate.DomainValidationOptions'

# Verify CNAME records in Namecheap match exactly
# Note: Some registrars add domain automatically, others don't
```

---

## Maintenance Windows

### Weekly Maintenance (Sundays 2:00 AM - 4:00 AM WAT)

**Tasks:**
1. Review CloudWatch logs for errors
2. Check for unused resources
3. Review security group rules
4. Verify backup completion
5. Update Helm chart dependencies
6. Check for Terraform provider updates

```bash
# Run weekly maintenance script
./scripts/weekly-maintenance.sh
```

### Monthly Maintenance (First Sunday 2:00 AM - 6:00 AM WAT)

**Tasks:**
1. Rotate developer credentials
2. Review IAM policies
3. Update base images
4. Patch EKS nodes (if needed)
5. Review and optimize costs
6. Update documentation

### EKS Version Updates

**Check for updates:**
```bash
aws eks describe-addon-versions --region us-east-1
```

**Update process:**
1. Create test environment (if available)
2. Update EKS version via Terraform
3. Update node group AMI
4. Verify application functionality
5. Monitor for 24 hours

---

## Emergency Contacts

| Role | Contact | Escalation |
|---|---|---|
| Primary On-Call | James Adewara | Slack: @jamesadewara |
| Secondary | AltSchool Support | support@altschoolafrica.com |
| AWS Support | AWS Console | Business Support (if subscribed) |

## Appendix

### Useful Commands Reference

```bash
# Terraform
terraform plan -target=module.vpc
terraform state list
terraform state show aws_eks_cluster.main
terraform output -json

# Kubernetes
kubectl get all -n retail-app
kubectl logs -f deployment/ui -n retail-app
kubectl exec -it <pod-name> -n retail-app -- /bin/sh
kubectl port-forward svc/ui 8080:80 -n retail-app

# Helm
helm list -n retail-app
helm get values retail-app -n retail-app
helm get manifest retail-app -n retail-app
helm template retail-app . -f values.yaml

# AWS
aws eks list-clusters --region us-east-1
aws ec2 describe-instances --filters "Name=tag:Project,Values=karatu-2025-capstone"
aws rds describe-db-instances --region us-east-1
aws dynamodb describe-table --table-name bedrock-carts --region us-east-1
aws s3 ls s3://bedrock-assets-jamesadewara --recursive
aws lambda list-functions --region us-east-1
```

### Log Locations

| Component | Log Group | Retention |
|---|---|---|
| EKS Control Plane | /aws/eks/project-bedrock-cluster/cluster | 7 days |
| Container Insights | /aws/containerinsights/project-bedrock-cluster/application | 7 days |
| Lambda | /aws/lambda/bedrock-asset-processor | 7 days |
| VPC Flow Logs | /aws/vpc/project-bedrock-vpc-flow-logs | 7 days |

### Resource Limits

| Resource | Current | Max | Notes |
|---|---|---|---|
| EKS Nodes | 2 | 3 | t3.micro |
| UI Pods | 2 | 10 | HPA enabled |
| Catalog Pods | 2 | 10 | HPA enabled |
| RDS Storage | 20 GB | 50 GB | Auto-scaling enabled |
| DynamoDB | On-demand | N/A | Pay per request |
| S3 Bucket | Unlimited | N/A | No versioning |

---

**Document Version:** 1.0
**Last Updated:** June 2026
**Author:** James Adewara
**Review Cycle:** Monthly
