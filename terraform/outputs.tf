output "cluster_name" {
  value = module.eks.cluster_name
}

output "service_hostname" {
  description = "Public hostname of the LoadBalancer"
  value       = try(kubernetes_service.lb.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "service_ip" {
  description = "Public IP of the LoadBalancer (if present)"
  value       = try(kubernetes_service.lb.status[0].load_balancer[0].ingress[0].ip, null)
}