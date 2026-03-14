# 環境固有の設定（共通値は .env → TF_VAR_ で注入）
env          = "prod"

# prod環境: スペックアップ、HA有効
db_tier      = "db-g1-small"
ha_enabled   = true
machine_type = "e2-medium"
