terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # GCSバックエンド（stateファイルをリモート管理）
  # 有効化手順: bootstrap/ を先に実行してGCSバケットを作成してから、
  # 以下のコメントを外して terraform init を実行
  # backend "gcs" {
  #   bucket = "myapp-terraform-state"
  #   prefix = "prod"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# API有効化
# =============================================================================
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# =============================================================================
# モジュール呼び出し
# =============================================================================

module "network" {
  source = "../../modules/network"

  prefix            = local.prefix
  region            = var.region
  subnet_cidr       = "10.10.0.0/24"       # prodはdevと別のCIDR
  private_services_cidr = "10.11.0.0"
  flow_log_sampling = 1.0                   # prod: 全量ログ

  depends_on = [google_project_service.apis]
}

module "database" {
  source = "../../modules/database"

  prefix                 = local.prefix
  region                 = var.region
  vpc_id                 = module.network.vpc_id
  private_vpc_connection = module.network.private_vpc_connection
  db_name                = var.db_name
  db_user                = var.db_user
  db_password            = var.db_password
  db_tier                = var.db_tier
  ha_enabled             = var.ha_enabled
  deletion_protection    = true  # 本番は削除保護ON
  backup_retention_days  = 30    # 本番は30日保持
}

module "security" {
  source = "../../modules/security"

  prefix             = local.prefix
  rate_limit_count   = 200   # 本番はレート制限を緩め
  rate_limit_interval = 60

  depends_on = [google_project_service.apis]
}

module "application" {
  source = "../../modules/application"

  prefix                   = local.prefix
  project_id               = var.project_id
  region                   = var.region
  zone                     = var.zone
  subnet_id                = module.network.subnet_id
  machine_type             = var.machine_type
  cloudsql_connection_name  = module.database.connection_name
  security_policy_id       = module.security.policy_id
  domain                   = var.domain
  db_secret_id             = module.database.secret_id
  db_name                  = "myapp"
  db_user                  = "myapp-app"

  depends_on = [google_project_service.apis]
}

locals {
  prefix = "${var.project_name}-${var.env}"  # myapp-prod
}
