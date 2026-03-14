project_id   = "your-gcp-project-id"
project_name = "myapp"
env          = "dev"
region       = "asia-northeast1"
zone         = "asia-northeast1-a"

# dev環境: 最小スペック、HA無効
db_tier      = "db-f1-micro"
ha_enabled   = false
machine_type = "e2-small"
domain       = "example.com"
