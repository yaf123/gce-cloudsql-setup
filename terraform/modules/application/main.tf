# =============================================================================
# サービスアカウント
# =============================================================================
resource "google_service_account" "web" {
  account_id   = "${var.prefix}-web-sa"
  display_name = "${var.prefix}-web Service Account"
}

resource "google_project_iam_member" "roles" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.web.email}"
}

# =============================================================================
# GCE インスタンス
# =============================================================================
resource "google_compute_instance" "web" {
  name         = "${var.prefix}-web"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_id
  }

  service_account {
    email  = google_service_account.web.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = file("${path.module}/templates/startup.sh")

  depends_on = [google_project_iam_member.roles]
}

# =============================================================================
# ロードバランサー
# =============================================================================

# 外部IP
resource "google_compute_global_address" "lb_ip" {
  name = "${var.prefix}-lb-ip"
}

# インスタンスグループ
resource "google_compute_instance_group" "web" {
  name = "${var.prefix}-ig"
  zone = var.zone

  instances = [google_compute_instance.web.self_link]

  named_port {
    name = "http"
    port = 80
  }

  lifecycle {
    replace_triggered_by = [google_compute_instance.web.id]
  }
}

# ヘルスチェック
resource "google_compute_health_check" "web" {
  name               = "${var.prefix}-hc"
  check_interval_sec = 10
  timeout_sec        = 5

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

# バックエンドサービス
resource "google_compute_backend_service" "web" {
  name                  = "${var.prefix}-backend"
  protocol              = "HTTP"
  port_name             = "http"
  health_checks         = [google_compute_health_check.web.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"
  security_policy       = var.security_policy_id

  backend {
    group = google_compute_instance_group.web.id
  }
}

# URLマップ
resource "google_compute_url_map" "web" {
  name            = "${var.prefix}-urlmap"
  default_service = google_compute_backend_service.web.id
}

# ドメインなし: HTTP直接
resource "google_compute_target_http_proxy" "web" {
  count   = var.domain == "" ? 1 : 0
  name    = "${var.prefix}-http-proxy"
  url_map = google_compute_url_map.web.id
}

resource "google_compute_global_forwarding_rule" "http_direct" {
  count                 = var.domain == "" ? 1 : 0
  name                  = "${var.prefix}-http-fw-rule"
  target                = google_compute_target_http_proxy.web[0].id
  ip_address            = google_compute_global_address.lb_ip.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ドメインあり: HTTPS + HTTPリダイレクト
resource "google_compute_managed_ssl_certificate" "web" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.prefix}-cert"

  managed {
    domains = [var.domain]
  }
}

resource "google_compute_target_https_proxy" "web" {
  count            = var.domain != "" ? 1 : 0
  name             = "${var.prefix}-https-proxy"
  url_map          = google_compute_url_map.web.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web[0].id]
}

resource "google_compute_global_forwarding_rule" "https" {
  count                 = var.domain != "" ? 1 : 0
  name                  = "${var.prefix}-https-fw-rule"
  target                = google_compute_target_https_proxy.web[0].id
  ip_address            = google_compute_global_address.lb_ip.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_url_map" "http_redirect" {
  count = var.domain != "" ? 1 : 0
  name  = "${var.prefix}-http-redirect"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "redirect" {
  count   = var.domain != "" ? 1 : 0
  name    = "${var.prefix}-http-redirect-proxy"
  url_map = google_compute_url_map.http_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "http_redirect" {
  count                 = var.domain != "" ? 1 : 0
  name                  = "${var.prefix}-http-redirect-fw-rule"
  target                = google_compute_target_http_proxy.redirect[0].id
  ip_address            = google_compute_global_address.lb_ip.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}
