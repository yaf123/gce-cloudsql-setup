#!/bin/bash
set -e

# =============================================================================
# 最小限の初期化（Ansible SSH接続の前提条件確認）
# =============================================================================

# Python確認（Ansibleの接続に必要、Debian 12には標準搭載）
if ! command -v python3 &> /dev/null; then
  apt-get update
  apt-get install -y python3
fi

# ログ出力
echo "$(date): GCE startup complete. Ready for Ansible provisioning." | tee -a /var/log/startup.log
