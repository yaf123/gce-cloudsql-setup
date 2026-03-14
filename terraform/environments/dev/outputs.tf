output "lb_ip_address" {
  description = "ロードバランサーの外部IPアドレス"
  value       = module.application.lb_ip_address
}

output "gce_internal_ip" {
  description = "GCEの内部IPアドレス"
  value       = module.application.gce_internal_ip
}

output "cloudsql_private_ip" {
  description = "Cloud SQLのPrivate IPアドレス"
  value       = module.database.private_ip
}

output "cloudsql_connection_name" {
  description = "Cloud SQL接続名"
  value       = module.database.connection_name
}

output "ssh_command" {
  description = "IAP経由SSH接続コマンド"
  value       = module.application.ssh_command
}
