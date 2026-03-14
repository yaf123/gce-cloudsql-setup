variable "prefix" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "project_id" {
  description = "GCPプロジェクトID"
  type        = string
}

variable "region" {
  description = "リージョン"
  type        = string
}

variable "zone" {
  description = "ゾーン"
  type        = string
}

variable "subnet_id" {
  description = "サブネットのID"
  type        = string
}

variable "machine_type" {
  description = "GCEマシンタイプ"
  type        = string
  default     = "e2-small"
}

variable "boot_image" {
  description = "ブートディスクのイメージ"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "boot_disk_size" {
  description = "ブートディスクサイズ(GB)"
  type        = number
  default     = 20
}

variable "cloudsql_connection_name" {
  description = "Cloud SQL接続名（Auth Proxy用）"
  type        = string
}

variable "security_policy_id" {
  description = "Cloud ArmorポリシーのID"
  type        = string
  default     = null
}

variable "domain" {
  description = "SSL証明書用ドメイン（空ならHTTPのみ）"
  type        = string
  default     = ""
}

variable "db_secret_id" {
  description = "Secret ManagerのシークレットID（DBパスワード）"
  type        = string
}

variable "db_name" {
  description = "データベース名"
  type        = string
}

variable "db_user" {
  description = "データベースユーザー名"
  type        = string
}
