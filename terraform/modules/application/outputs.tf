output "lb_ip_address" {
  description = "ロードバランサーの外部IPアドレス"
  value       = google_compute_global_address.lb_ip.address
}

output "gce_internal_ip" {
  description = "GCEの内部IPアドレス"
  value       = google_compute_instance.web.network_interface[0].network_ip
}

output "gce_name" {
  description = "GCEインスタンス名"
  value       = google_compute_instance.web.name
}

output "ssh_command" {
  description = "IAP経由SSH接続コマンド"
  value       = "gcloud compute ssh ${google_compute_instance.web.name} --zone=${var.zone} --tunnel-through-iap"
}
