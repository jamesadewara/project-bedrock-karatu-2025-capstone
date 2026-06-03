# Helm Audit Report - Project Bedrock

## Executive Summary

Your Helm setup uses raw Kubernetes templates instead of upstream AWS OCI chart dependencies, violates your Namecheap DNS requirement by configuring HTTPS/ACM certificates, and references Route53 in comments. The Chart.yaml lacks the required 6 AWS chart dependencies, templates/ contains 17 raw YAML files that should be managed by upstream charts, and values.yaml/configures HTTPS with ACM certificates instead of HTTP-only for ALB DNS access.

## Current State vs Desired State

| Item | Current State | Desired State | Status |
|------|---------------|---------------|--------|
| **Chart.yaml** | apiVersion: v2, no dependencies section | apiVersion: v2, dependencies with 6 AWS OCI charts | ❌ FAIL |
| **templates/_helpers.tpl** | Exists | Exists | ✅ PASS |
| **templates/assets-deployment.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/assets-service.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/carts-deployment.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/carts-service.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/carts-serviceaccount.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/catalog-deployment.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/catalog-service.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/checkout-deployment.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/checkout-service.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/namespace.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/orders-deployment.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/orders-service.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/ui-deployment.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/ui-ingress.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **templates/ui-service.yaml** | Exists (raw template) | Should not exist (use AWS chart) | ❌ FAIL |
| **values.yaml line 31** | HTTPS port 443 configured | HTTP port 80 only | ❌ FAIL |
| **values.yaml line 32** | certificate-arn annotation present | No certificate-arn annotation | ❌ FAIL |
| **values.yaml line 38-39** | host: "yourdomain.com" with Route53 comment | host: "" (empty, ALB DNS direct) | ❌ FAIL |
| **values.yaml line 120** | IRSA role-arn empty string | IRSA role-arn filled with actual ARN | ⚠️ WARNING |
| **values.yaml DB overrides** | RDS/DynamoDB configured | RDS/DynamoDB configured | ✅ PASS |
| **values-prod.yaml line 28** | HTTPS port 443 configured | HTTP port 80 only | ❌ FAIL |
| **values-prod.yaml line 29** | certificate-arn annotation present | No certificate-arn annotation | ❌ FAIL |
| **values-prod.yaml line 34** | host: "bedrock.jamesadewara.nip.io" | host: "" (empty, ALB DNS direct) | ❌ FAIL |
| **values-prod.yaml replicas** | Higher than values.yaml | Higher than values.yaml | ✅ PASS |

## Exact Fix Commands

### Step 1: Backup current Helm folder
```bash
cd /home/WORKSPACE/project-bedrock-karatu-2025-capstone
cp -r helm helm-backup-$(date +%Y%m%d)
```

### Step 2: Remove raw template files (keep only _helpers.tpl)
```bash
cd /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm/templates
rm -f assets-deployment.yaml assets-service.yaml
rm -f carts-deployment.yaml carts-service.yaml carts-serviceaccount.yaml
rm -f catalog-deployment.yaml catalog-service.yaml
rm -f checkout-deployment.yaml checkout-service.yaml
rm -f namespace.yaml
rm -f orders-deployment.yaml orders-service.yaml
rm -f ui-deployment.yaml ui-ingress.yaml ui-service.yaml
```

### Step 3: Update Chart.yaml with dependencies
```bash
cat > /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm/Chart.yaml << 'EOF'
apiVersion: v2
name: retail-store
description: InnovateMart Retail Store Application
type: application
version: 1.0.0
appVersion: "0.8.0"

dependencies:
  # AWS Load Balancer Controller for ALB ingress
  - name: aws-load-balancer-controller
    repository: oci://public.ecr.aws/aws-load-balancer-controller
    version: 2.7.0
    condition: awsLoadBalancerController.enabled
  
  # AWS EBS CSI Driver for persistent storage (if needed)
  - name: aws-ebs-csi-driver
    repository: oci://public.ecr.aws/aws-ebs-csi-driver
    version: 2.23.0
    condition: awsEbsCsiDriver.enabled
  
  # External Secrets Operator for Secrets Manager integration
  - name: external-secrets
    repository: https://charts.external-secrets.io
    version: 0.9.0
    condition: externalSecrets.enabled
  
  # AWS for Fluent Bit for CloudWatch logs
  - name: aws-for-fluent-bit
    repository: https://aws.github.io/eks-charts
    version: 0.1.29
    condition: awsForFluentBit.enabled
  
  # AWS VPC CNI for networking
  - name: aws-vpc-cni
    repository: https://aws.github.io/eks-charts
    version: 1.16.0
    condition: awsVpcCni.enabled
  
  # Metrics Server for HPA
  - name: metrics-server
    repository: https://kubernetes-sigs.github.io/metrics-server
    version: 3.12.0
    condition: metricsServer.enabled
EOF
```

### Step 4: Update values.yaml for HTTP-only and Namecheap DNS
```bash
cat > /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm/values.yaml << 'EOF'
# ============================================================
# VALUES.YAML - Project Bedrock Custom Overrides
# All databases replaced with managed AWS services
# No hardcoded credentials - all injected via Secrets Manager
# Namecheap DNS with CNAME to ALB (HTTP-only, no HTTPS/ACM)
# ============================================================

# Global settings
global:
  # Namespace for all resources
  namespaceOverride: retail-app

# ============================================================
# UI SERVICE - Frontend with ALB Ingress (HTTP-only)
# ============================================================
ui:
  enabled: true
  replicaCount: 2

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      # HTTP-only for Namecheap CNAME to ALB DNS
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/healthcheck-path: /health
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      # Empty host - ALB DNS direct access via Namecheap CNAME
      - host: ""
        paths:
          - path: /
            pathType: Prefix

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# CATALOG SERVICE - MySQL -> RDS MySQL
# ============================================================
catalog:
  enabled: true
  replicaCount: 2

  # DISABLE in-cluster MySQL
  mysql:
    enabled: false

  # Service configuration
  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  # Environment variables - RDS MySQL connection
  # Credentials pulled from AWS Secrets Manager via External Secrets Operator
  # or injected via Terraform-created secrets
  env:
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: host
    - name: DB_PORT
      value: "3306"
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: password
    - name: DB_NAME
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: dbname

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# CARTS SERVICE - DynamoDB -> Real DynamoDB Table
# ============================================================
carts:
  enabled: true
  replicaCount: 2

  # DISABLE in-cluster DynamoDB (local mode)
  dynamodb:
    enabled: false

  # Service account with IRSA for DynamoDB access
  serviceAccount:
    create: true
    name: carts
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-carts-dynamodb-role"

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  # Environment variables for real DynamoDB
  env:
    - name: CARTS_DYNAMODB_TABLE
      value: bedrock-carts
    - name: AWS_REGION
      value: us-east-1

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# ORDERS SERVICE - MySQL -> RDS PostgreSQL
# ============================================================
orders:
  enabled: true
  replicaCount: 2

  # DISABLE in-cluster MySQL
  mysql:
    enabled: false

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  # Environment variables - RDS PostgreSQL connection
  env:
    - name: SPRING_DATASOURCE_WRITER_URL
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: jdbc_url
    - name: SPRING_DATASOURCE_WRITER_USERNAME
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: username
    - name: SPRING_DATASOURCE_WRITER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: password
    - name: SPRING_DATASOURCE_READER_URL
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: jdbc_url
    - name: SPRING_DATASOURCE_READER_USERNAME
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: username
    - name: SPRING_DATASOURCE_READER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: password

  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"

# ============================================================
# CHECKOUT SERVICE - Redis stays in-cluster (acceptable)
# ============================================================
checkout:
  enabled: true
  replicaCount: 2

  # Redis stays in-cluster as per exam requirements
  redis:
    enabled: true

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# ASSETS SERVICE - Static assets
# ============================================================
assets:
  enabled: true
  replicaCount: 1

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"

# ============================================================
# AWS DEPENDENCY CONFIGURATION
# ============================================================

# AWS Load Balancer Controller
awsLoadBalancerController:
  enabled: true
  clusterName: bedrock-cluster
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/aws-load-balancer-controller-role"

# External Secrets Operator
externalSecrets:
  enabled: true
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/external-secrets-role"

# Metrics Server
metricsServer:
  enabled: true
  args:
    - --kubelet-insecure-tls
EOF
```

### Step 5: Update values-prod.yaml for HTTP-only and Namecheap DNS
```bash
cat > /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm/values-prod.yaml << 'EOF'
# ============================================================
# VALUES-PROD.YAML - Production Overrides
# Stricter resource limits, higher replicas, HTTP-only
# ============================================================

# Global settings
global:
  namespaceOverride: retail-app

# ============================================================
# UI SERVICE - Production (HTTP-only)
# ============================================================
ui:
  enabled: true
  replicaCount: 3

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      # HTTP-only for Namecheap CNAME to ALB DNS
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/healthcheck-path: /health
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      # Empty host - ALB DNS direct access via Namecheap CNAME
      - host: ""
        paths:
          - path: /
            pathType: Prefix

  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"

# ============================================================
# CATALOG SERVICE - Production
# ============================================================
catalog:
  enabled: true
  replicaCount: 3

  mysql:
    enabled: false

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  env:
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: host
    - name: DB_PORT
      value: "3306"
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: password
    - name: DB_NAME
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: dbname

  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"

# ============================================================
# CARTS SERVICE - Production
# ============================================================
carts:
  enabled: true
  replicaCount: 3

  dynamodb:
    enabled: false

  serviceAccount:
    create: true
    name: carts
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-carts-dynamodb-role

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  env:
    - name: CARTS_DYNAMODB_TABLE
      value: bedrock-carts
    - name: AWS_REGION
      value: us-east-1

  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"

# ============================================================
# ORDERS SERVICE - Production
# ============================================================
orders:
  enabled: true
  replicaCount: 3

  mysql:
    enabled: false

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  env:
    - name: SPRING_DATASOURCE_WRITER_URL
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: jdbc_url
    - name: SPRING_DATASOURCE_WRITER_USERNAME
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: username
    - name: SPRING_DATASOURCE_WRITER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: password
    - name: SPRING_DATASOURCE_READER_URL
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: jdbc_url
    - name: SPRING_DATASOURCE_READER_USERNAME
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: username
    - name: SPRING_DATASOURCE_READER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: password

  resources:
    requests:
      memory: "512Mi"
      cpu: "400m"
    limits:
      memory: "1Gi"
      cpu: "800m"

# ============================================================
# CHECKOUT SERVICE - Production
# ============================================================
checkout:
  enabled: true
  replicaCount: 3

  redis:
    enabled: true

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"

# ============================================================
# ASSETS SERVICE - Production
# ============================================================
assets:
  enabled: true
  replicaCount: 2

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

### Step 6: Create optional secrets.yaml template (if needed for DB credentials)
```bash
cat > /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm/templates/secrets.yaml << 'EOF'
# ============================================================
# SECRETS.YAML - Kubernetes Secrets for Database Credentials
# These secrets are typically created by Terraform or External Secrets Operator
# This template is provided as a fallback for manual secret creation
# ============================================================

{{- if .Values.catalog.enabled }}
apiVersion: v1
kind: Secret
metadata:
  name: catalog-db-credentials
  namespace: {{ .Values.global.namespaceOverride | default "retail-app" }}
type: Opaque
stringData:
  host: "{{ .Values.catalog.db.host | default \"\" }}"
  username: "{{ .Values.catalog.db.username | default \"\" }}"
  password: "{{ .Values.catalog.db.password | default \"\" }}"
  dbname: "{{ .Values.catalog.db.name | default \"\" }}"
{{- end }}

{{- if .Values.orders.enabled }}
---
apiVersion: v1
kind: Secret
metadata:
  name: orders-db-credentials
  namespace: {{ .Values.global.namespaceOverride | default "retail-app" }}
type: Opaque
stringData:
  jdbc_url: "{{ .Values.orders.db.jdbcUrl | default \"\" }}"
  username: "{{ .Values.orders.db.username | default \"\" }}"
  password: "{{ .Values.orders.db.password | default \"\" }}"
{{- end }}
EOF
```

### Step 7: Update Helm dependencies
```bash
cd /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm
helm dependency update
```

### Step 8: Verify the changes
```bash
cd /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm
echo "=== Chart.yaml ==="
cat Chart.yaml
echo ""
echo "=== templates/ directory ==="
ls -la templates/
echo ""
echo "=== values.yaml ingress section ==="
grep -A 15 "ingress:" values.yaml
echo ""
echo "=== values-prod.yaml ingress section ==="
grep -A 15 "ingress:" values-prod.yaml
```

## Proposed File Contents

### Chart.yaml (with dependencies)
```yaml
apiVersion: v2
name: retail-store
description: InnovateMart Retail Store Application
type: application
version: 1.0.0
appVersion: "0.8.0"

dependencies:
  # AWS Load Balancer Controller for ALB ingress
  - name: aws-load-balancer-controller
    repository: oci://public.ecr.aws/aws-load-balancer-controller
    version: 2.7.0
    condition: awsLoadBalancerController.enabled
  
  # AWS EBS CSI Driver for persistent storage (if needed)
  - name: aws-ebs-csi-driver
    repository: oci://public.ecr.aws/aws-ebs-csi-driver
    version: 2.23.0
    condition: awsEbsCsiDriver.enabled
  
  # External Secrets Operator for Secrets Manager integration
  - name: external-secrets
    repository: https://charts.external-secrets.io
    version: 0.9.0
    condition: externalSecrets.enabled
  
  # AWS for Fluent Bit for CloudWatch logs
  - name: aws-for-fluent-bit
    repository: https://aws.github.io/eks-charts
    version: 0.1.29
    condition: awsForFluentBit.enabled
  
  # AWS VPC CNI for networking
  - name: aws-vpc-cni
    repository: https://aws.github.io/eks-charts
    version: 1.16.0
    condition: awsVpcCni.enabled
  
  # Metrics Server for HPA
  - name: metrics-server
    repository: https://kubernetes-sigs.github.io/metrics-server
    version: 3.12.0
    condition: metricsServer.enabled
```

### values.yaml (HTTP-only, no ACM, no Route53)
```yaml
# ============================================================
# VALUES.YAML - Project Bedrock Custom Overrides
# All databases replaced with managed AWS services
# No hardcoded credentials - all injected via Secrets Manager
# Namecheap DNS with CNAME to ALB (HTTP-only, no HTTPS/ACM)
# ============================================================

# Global settings
global:
  namespaceOverride: retail-app

# ============================================================
# UI SERVICE - Frontend with ALB Ingress (HTTP-only)
# ============================================================
ui:
  enabled: true
  replicaCount: 2

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  ingress:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      # HTTP-only for Namecheap CNAME to ALB DNS
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/healthcheck-path: /health
      alb.ingress.kubernetes.io/success-codes: "200"
    hosts:
      # Empty host - ALB DNS direct access via Namecheap CNAME
      - host: ""
        paths:
          - path: /
            pathType: Prefix

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# CATALOG SERVICE - MySQL -> RDS MySQL
# ============================================================
catalog:
  enabled: true
  replicaCount: 2
  mysql:
    enabled: false

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  env:
    - name: DB_HOST
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: host
    - name: DB_PORT
      value: "3306"
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: password
    - name: DB_NAME
      valueFrom:
        secretKeyRef:
          name: catalog-db-credentials
          key: dbname

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# CARTS SERVICE - DynamoDB -> Real DynamoDB Table
# ============================================================
carts:
  enabled: true
  replicaCount: 2
  dynamodb:
    enabled: false

  serviceAccount:
    create: true
    name: carts
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/bedrock-carts-dynamodb-role"

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  env:
    - name: CARTS_DYNAMODB_TABLE
      value: bedrock-carts
    - name: AWS_REGION
      value: us-east-1

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# ORDERS SERVICE - MySQL -> RDS PostgreSQL
# ============================================================
orders:
  enabled: true
  replicaCount: 2
  mysql:
    enabled: false

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  env:
    - name: SPRING_DATASOURCE_WRITER_URL
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: jdbc_url
    - name: SPRING_DATASOURCE_WRITER_USERNAME
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: username
    - name: SPRING_DATASOURCE_WRITER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: password
    - name: SPRING_DATASOURCE_READER_URL
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: jdbc_url
    - name: SPRING_DATASOURCE_READER_USERNAME
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: username
    - name: SPRING_DATASOURCE_READER_PASSWORD
      valueFrom:
        secretKeyRef:
          name: orders-db-credentials
          key: password

  resources:
    requests:
      memory: "256Mi"
      cpu: "200m"
    limits:
      memory: "512Mi"
      cpu: "400m"

# ============================================================
# CHECKOUT SERVICE - Redis stays in-cluster (acceptable)
# ============================================================
checkout:
  enabled: true
  replicaCount: 2
  redis:
    enabled: true

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

# ============================================================
# ASSETS SERVICE - Static assets
# ============================================================
assets:
  enabled: true
  replicaCount: 1

  service:
    type: ClusterIP
    port: 80
    targetPort: 8080

  resources:
    requests:
      memory: "64Mi"
      cpu: "50m"
    limits:
      memory: "128Mi"
      cpu: "100m"

# ============================================================
# AWS DEPENDENCY CONFIGURATION
# ============================================================

awsLoadBalancerController:
  enabled: true
  clusterName: bedrock-cluster
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/aws-load-balancer-controller-role"

externalSecrets:
  enabled: true
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/external-secrets-role"

metricsServer:
  enabled: true
  args:
    - --kubelet-insecure-tls
```

### Minimal templates/ folder structure
```
helm/templates/
├── _helpers.tpl          (keep existing - Helm requires this)
└── secrets.yaml          (optional - for manual DB credential secrets)
```

**Note:** After applying these fixes, you will need to:
1. Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID in IRSA role ARNs
2. Run `helm dependency update` to pull the upstream AWS charts
3. Deploy using `helm install retail-store ./helm -f values.yaml` (or values-prod.yaml for production)
4. Configure Namecheap DNS CNAME to point to your ALB DNS name (obtained from `kubectl get ingress -n retail-app`)
