data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

# Kubernetes Provider for EKS
provider "kubernetes" {
  host                   = try(data.aws_eks_cluster.this.endpoint, "")
  cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.this.certificate_authority[0].data), "")
  token                  = try(data.aws_eks_cluster_auth.this.token, "")
}

# Helm Provider for EKS Add-ons
provider "helm" {
  kubernetes {
    host                   = try(data.aws_eks_cluster.this.endpoint, "")
    cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.this.certificate_authority[0].data), "")
    token                  = try(data.aws_eks_cluster_auth.this.token, "")
  }
}
