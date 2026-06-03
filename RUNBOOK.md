# karatu-2025-capstone 

cd terraform 
aws s3api create-bucket   --bucket karatu-terraform-state-jamesadewara   --region us-east-1

terraform plan

terraform apply > ../grading.json

# 1. Update kubeconfig (critical after every terraform apply)
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1

# 2. Verify cluster connection
kubectl get nodes

# 3. Deploy/upgrade Helm chart
cd /home/WORKSPACE/project-bedrock-karatu-2025-capstone/helm
helm dependency update
helm upgrade --install retail-app . \
  --namespace retail-app \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m

# 4. Verify deployment
kubectl get pods -n retail-app
kubectl get ingress -n retail-app

# 5. Get ALB DNS
kubectl get ingress -n retail-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'


cd ../helm
# Install ALB controller directly (not as dependency)

helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install each service separately with OCI
# Download and apply the official manifest
kubectl apply -f https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml

# Wait for deployment
kubectl wait --for=condition=available deployments --all -n retail-app

# Get URL
kubectl get svc ui -n retail-app

# Install Fluent Bit for CloudWatch logs
helm install aws-for-fluent-bit eks/aws-for-fluent-bit \
  --namespace kube-system \
  --set cloudWatch.enabled=true \
  --set cloudWatch.region=us-east-1 \
  --set cloudWatch.logGroupName=/aws/eks/project-bedrock-cluster/application \
  --set cloudWatch.logGroupTemplate=/aws/eks/project-bedrock-cluster/$kubernetes['namespace_name']

helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=$(terraform output -raw vpc_id)

helm dependency update

# Deploy
helm upgrade --install retail-app . \
  --namespace retail-app \
  --create-namespace \
  --values values.yaml \
  --wait \
  --timeout 10m



What You Need to Replace
In values.yaml and values-prod.yaml, find:
eks.amazonaws.com/role-arn: "arn:aws:iam::{YOUR_ACCOUNT_ID}:role/bedrock-carts-dynamodb-role"

Replace YOUR_ACCOUNT_ID with your actual AWS account ID. Get it from:
```bash
aws sts get-caller-identity --query Account --output text
```

# Check ALL namespaces
kubectl get namespaces

# Check ALL deployments
kubectl get deployments --all-namespaces | grep -E "ui|catalog|carts|orders|checkout"

# Check ALL services
kubectl get services --all-namespaces | grep -E "ui|catalog|carts|orders|checkout"

# Check ALL pods
kubectl get pods --all-namespaces | grep -E "ui|catalog|carts|orders|checkout"

# Check pods
kubectl get pods -n retail-app

# Get ALB DNS (your URL)
kubectl get ingress -n retail-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# Test
curl -I http://<<ALB-DNS>