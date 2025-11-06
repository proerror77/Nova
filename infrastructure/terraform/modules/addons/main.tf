# ============================================================================
# Kubernetes Providers Configuration
# ============================================================================

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# ============================================================================
# EKS Add-ons (AWS managed)
# ============================================================================

resource "aws_eks_addon" "coredns" {
  cluster_name             = var.cluster_name
  addon_name               = "coredns"
  addon_version            = var.coredns_version
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-coredns"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = var.cluster_name
  addon_name               = "kube-proxy"
  addon_version            = var.kube_proxy_version
  resolve_conflicts_on_create = "OVERWRITE"

  tags = {
    Name = "${var.cluster_name}-kube-proxy"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = var.cluster_name
  addon_name               = "vpc-cni"
  addon_version            = var.vpc_cni_version
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn = aws_iam_role.vpc_cni.arn

  tags = {
    Name = "${var.cluster_name}-vpc-cni"
  }
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_driver_version
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn = var.ebs_csi_role_arn

  tags = {
    Name = "${var.cluster_name}-ebs-csi"
  }
}

# ============================================================================
# VPC CNI IAM Role
# ============================================================================

resource "aws_iam_role" "vpc_cni" {
  name = "${var.cluster_name}-vpc-cni-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.cluster_oidc_issuer_url
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.vpc_cni.name
}

# ============================================================================
# Namespaces for Addons
# ============================================================================

resource "kubernetes_namespace" "addons" {
  for_each = toset([
    "kube-system",
    "kube-monitoring",
    "ingress-nginx",
    "cert-manager",
    "argocd"
  ])

  metadata {
    name = each.value

    labels = {
      "app.kubernetes.io/name"       = each.value
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ============================================================================
# Helm Chart: AWS Load Balancer Controller
# ============================================================================

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = kubernetes_namespace.addons["kube-system"].metadata[0].name
  create_namespace = false
  version          = "2.6.2"

  values = [
    yamlencode({
      serviceAccount = {
        name = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.alb_controller_role_arn
        }
      }
      clusterName = var.cluster_name
      replicaCount = 2
    })
  ]

  depends_on = [kubernetes_namespace.addons]
}

# ============================================================================
# Helm Chart: Metrics Server (for HPA)
# ============================================================================

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  namespace        = kubernetes_namespace.addons["kube-system"].metadata[0].name
  create_namespace = false
  version          = "3.11.0"

  depends_on = [kubernetes_namespace.addons]
}

# ============================================================================
# Helm Chart: Cert-Manager
# ============================================================================

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = kubernetes_namespace.addons["cert-manager"].metadata[0].name
  create_namespace = false
  version          = "v1.13.2"

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.addons]
}

# ============================================================================
# Helm Chart: ArgoCD
# ============================================================================

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.addons["argocd"].metadata[0].name
  create_namespace = false
  version          = "5.50.3"

  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
        }
      }
      repoServer = {
        autoscaling = {
          enabled     = true
          minReplicas = 2
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.addons,
    helm_release.aws_load_balancer_controller
  ]
}

# ============================================================================
# Helm Chart: Prometheus (optional monitoring)
# ============================================================================

resource "helm_release" "prometheus" {
  count = var.enable_monitoring ? 1 : 0

  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace.addons["kube-monitoring"].metadata[0].name
  create_namespace = false
  version          = "54.0.0"

  depends_on = [kubernetes_namespace.addons]
}
