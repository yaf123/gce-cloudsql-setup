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
  default     = "dev"
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
  default     = "db-f1-micro"
}

variable "ha_enabled" {
  description = "Cloud SQL高可用性"
  type        = bool
  default     = false  # dev環境はHA不要
}

variable "machine_type" {
  description = "GCEマシンタイプ"
  type        = string
  default     = "e2-small"
}

variable "domain" {
  description = "SSL証明書用ドメイン（空ならHTTPのみ）"
  type        = string
  default     = ""
}
