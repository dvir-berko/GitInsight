# Grab two AZs for a simple 2-AZ VPC
data "aws_availability_zones" "available" {}

# --- VPC ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project = var.project_name
  }
}

# --- EKS ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.27.0"

  cluster_name    = "${var.project_name}-eks"
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Managed node group
  eks_managed_node_groups = {
    default = {
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Project = var.project_name
  }
}

# --- Kubernetes namespace, deployment, service ---
resource "kubernetes_namespace" "ns" {
  metadata {
    name = var.project_name
  }
  depends_on = [module.eks]
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.project_name
    namespace = kubernetes_namespace.ns.metadata[0].name
    labels = { app = var.project_name }
  }
  spec {
    replicas = var.replicas
    selector { match_labels = { app = var.project_name } }
    template {
      metadata { labels = { app = var.project_name } }
      spec {
        container {
          name  = "${var.project_name}-api"
          image = var.docker_image
          port { container_port = 8080 }

          env {
            name  = "DATA_FILE"
            value = "/app/insights.json"
          }

          # Liveness/readiness for basic health
          liveness_probe {
            http_get { path = "/insights" port = 8080 }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
          readiness_probe {
            http_get { path = "/insights" port = 8080 }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
  depends_on = [module.eks]
}

resource "kubernetes_service" "lb" {
  metadata {
    name      = "${var.project_name}-svc"
    namespace = kubernetes_namespace.ns.metadata[0].name
    annotations = {
      # Ensure an NLB is provisioned by AWS load balancer controller (managed by EKS)
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
    labels = { app = var.project_name }
  }
  spec {
    selector = { app = var.project_name }
    port {
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }
    type = "LoadBalancer"
  }
  depends_on = [module.eks]
}