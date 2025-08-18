variable "project_name" {
  type        = string
  default     = "gitinsight"
  description = "Project prefix for resource names"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "cluster_version" {
  type        = string
  default     = "1.31"
  description = "EKS Kubernetes version"
}

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.small"]
}

variable "desired_size" { default = 2 }
variable "min_size"     { default = 1 }
variable "max_size"     { default = 3 }

variable "docker_image" {
  type        = string
  description = "Container image to deploy (e.g., YOUR_DH_USERNAME/gitinsight:latest)"
}

variable "replicas" {
  type        = number
  default     = 3
}