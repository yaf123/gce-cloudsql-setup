project_id   = "your-gcp-project-id"
project_name = "myapp"
env          = "prod"
region       = "asia-northeast1"
zone         = "asia-northeast1-a"

# prod環境: スペックアップ、HA有効
db_tier      = "db-g1-small"
ha_enabled   = true
machine_type = "e2-medium"
# domain     = "example.com"  # ドメインがあれば設定
