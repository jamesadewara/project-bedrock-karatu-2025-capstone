# karatu-2025-capstone 

cd terraform 
aws s3api create-bucket   --bucket karatu-terraform-state-jamesadewara   --region us-east-1

terraform plan

terraform apply > ../grading.json

cd ../helm
# Install ALB controller directly (not as dependency)
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=$(terraform output -raw vpc_id)