# EKS Cluster Role
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

# Get current AWS region
data "aws_region" "current" {}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Node Group Role
resource "aws_iam_role" "node_group" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Security Group for EKS Nodes
resource "aws_security_group" "nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "Security group for EKS nodes"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-nodes-sg"
  })
}

# Allow control plane to communicate with kubelet (port 10250)
resource "aws_security_group_rule" "control_plane_to_nodes_kubelet" {
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.nodes.id
  description       = "Allow control plane to kubelet"
}

# Allow control plane to communicate with extension API servers (port 443)
resource "aws_security_group_rule" "control_plane_to_nodes_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  self              = true
  security_group_id = aws_security_group.nodes.id
  description       = "Allow control plane to extension API servers/webhooks"
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.eks_public_access_cidrs
    security_group_ids      = [aws_security_group.nodes.id]
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = var.common_tags
}

# OIDC Provider for IRSA
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.common_tags
}

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.aws_eks_node_group_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = 6 # Bumped from 4 to 6 to let fresh nodes take on the workloads
    min_size     = 2
    max_size     = 8 # Bumped from 5 to 8 to give the scheduler scaling headroom
  }

  update_config {
    max_unavailable_percentage = 25
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]

  tags = var.common_tags
}

# Enable IP Prefix Delegation on aws-node DaemonSet
# Lifts pod limit on t3.medium from 17 to 110 pods
resource "null_resource" "enable_prefix_delegation" {
  triggers = {
    cluster_id = aws_eks_cluster.main.id
  }

  provisioner "local-exec" {
    command     = <<-EOT
      aws eks update-kubeconfig \
        --name ${aws_eks_cluster.main.name} \
        --region ${data.aws_region.current.name} && \
      kubectl patch daemonset aws-node -n kube-system \
        --type='json' \
        -p='[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "ENABLE_PREFIX_DELEGATION",
              "value": "true"
            }
          },
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/env/-",
            "value": {
              "name": "WARM_PREFIX_TARGET",
              "value": "1"
            }
          }
        ]' || true
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.node_cni
  ]
}

# AWS Load Balancer Controller IAM Role (IRSA)
resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.common_tags
}

# AWS Load Balancer Controller IAM Policy (from official AWS policy file)
resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller-policy"
  description = "Policy for AWS Load Balancer Controller to manage ALBs and target groups"
  policy      = file("${path.module}/alb_controller_policy.json")

  tags = var.common_tags
}

# Attach policy to ALB controller role
resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# Deploy AWS Load Balancer Controller via Helm (local chart)
resource "helm_release" "alb_controller" {
  name             = "aws-load-balancer-controller"
  chart            = "${path.module}/charts/aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "replicaCount"
    value = "1"
  }

  # Enable service account with IRSA annotation
  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  # Lightweight resource constraints for Free Tier t3.small instances
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  # Enable logging
  set {
    name  = "enableLogging"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.fluent_bit.arn
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.alb_controller,
    kubernetes_namespace.app
  ]
}

# AWS Load Balancer Controller - IAM role & policy created

# CloudWatch Log Group for container logs (lightweight FluentBit)
resource "aws_cloudwatch_log_group" "container_logs" {
  name              = "/aws/eks/${var.cluster_name}/containers"
  retention_in_days = 3

  tags = var.common_tags

  depends_on = [aws_eks_cluster.main]
}

# IAM Role for aws-fluent-bit (IRSA)
resource "aws_iam_role" "fluent_bit" {
  name = "${var.cluster_name}-fluent-bit-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:fluent-bit"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "fluent_bit" {
  role       = aws_iam_role.fluent_bit.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Deploy aws-fluent-bit via Helm (lightweight alternative to managed addon)
resource "helm_release" "fluent_bit" {
  name             = "aws-fluent-bit"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-for-fluent-bit"
  namespace        = "amazon-cloudwatch"
  create_namespace = true
  version          = "0.1.33"

  # FIX: Correct escaping for annotations mapping to IAM IRSA role
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.fluent_bit.arn
  }

  # FIX: Correct parameter blocks using 'cloudWatchLogs' structure
  set {
    name  = "cloudWatchLogs.enabled"
    value = "true"
  }

  set {
    name  = "cloudWatchLogs.region"
    value = data.aws_region.current.name
  }

  set {
    name  = "cloudWatchLogs.logGroupName"
    value = aws_cloudwatch_log_group.container_logs.name
  }

  set {
    name  = "cloudWatchLogs.autoCreateGroup"
    value = "false"
  }

  # Minimal resource constraints for Free Tier t3.small nodes (Kept your perfect limits!)
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "50Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "100Mi"
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.fluent_bit,
    aws_cloudwatch_log_group.container_logs
  ]
}

# Create Application Namespace
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/name" = "retail-app"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# AWS-AUTH ConfigMap - Map IAM User to K8s RBAC
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapUsers = yamlencode([{
      userarn  = var.dev_user_arn
      username = "bedrock-dev-view"
      groups   = ["view"]
    }])
  }

  force = true

  depends_on = [aws_eks_node_group.main]
}
