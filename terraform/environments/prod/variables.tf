variable "project_id" {
  description = "GCPプロジェクトID"
  type        = string
}

variable "project_name" {
  description = "プロジェクト名（リソース名のプレフィックス）"
  type        = string
  default     = "myapp"
}

variable "env" {
  description = "環境名"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "リージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "ゾーン"
  type        = string
  default     = "asia-northeast1-a"
}

variable "db_password" {
  description = "DBパスワード"
  type        = string
  sensitive   = true
}

variable "db_tier" {
  description = "Cloud SQLマシンタイプ"
  type        = string
  default     = "db-g1-small"  # 本番はスペックアップ
}

variable "ha_enabled" {
  description = "Cloud SQL高可用性"
  type        = bool
  default     = true  # 本番はHA有効
}

variable "machine_type" {
  description = "GCEマシンタイプ"
  type        = string
  default     = "e2-medium"  # 本番はスペックアップ
}

variable "domain" {
  description = "SSL証明書用ドメイン"
  type        = string
  default     = ""
}
