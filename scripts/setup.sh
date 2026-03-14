#!/bin/bash
set -e

# =============================================================================
# GCE + Cloud SQL セットアップスクリプト
# .env を読み込んで Terraform / Ansible を実行する
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${ROOT_DIR}/.env"

# .env チェック
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env ファイルが見つかりません"
  echo "  cp .env.example .env"
  echo "  vi .env"
  exit 1
fi

# .env 読み込み（変数展開対応）
set -a
source "$ENV_FILE"
set +a

# Terraform 用の TF_VAR_ 環境変数をエクスポート
export TF_VAR_project_id="$GCP_PROJECT_ID"
export TF_VAR_project_name="$PROJECT_NAME"
export TF_VAR_region="$GCP_REGION"
export TF_VAR_zone="$GCP_ZONE"
export TF_VAR_domain="${DOMAIN:-}"
export TF_VAR_bucket_name="$TFSTATE_BUCKET"
export TF_VAR_db_password="${DB_PASSWORD:-}"

# 使用方法
usage() {
  echo "Usage: $0 <command> [environment]"
  echo ""
  echo "Commands:"
  echo "  bootstrap          GCSバケット作成（初回のみ）"
  echo "  plan    <dev|prod> Terraform plan"
  echo "  apply   <dev|prod> Terraform apply"
  echo "  destroy <dev|prod> Terraform destroy"
  echo "  ansible <dev|prod> Ansible playbook 実行"
  echo "  ansible-tag <dev|prod> <tag>  特定ロールのみ実行"
  echo "  info               現在の設定値を表示"
  echo ""
  echo "Examples:"
  echo "  $0 info                    # 設定確認"
  echo "  $0 bootstrap               # GCSバケット作成"
  echo "  $0 plan dev                # dev環境の実行計画"
  echo "  $0 apply dev               # dev環境にインフラ構築"
  echo "  $0 ansible dev             # dev環境にAnsible実行"
  echo "  $0 ansible-tag dev webapp  # webappロールのみ実行"
}

# 設定値表示
cmd_info() {
  echo "=== 現在の設定値 ==="
  echo "GCP_PROJECT_ID : $GCP_PROJECT_ID"
  echo "PROJECT_NAME   : $PROJECT_NAME"
  echo "GCP_REGION     : $GCP_REGION"
  echo "GCP_ZONE       : $GCP_ZONE"
  echo "DOMAIN         : ${DOMAIN:-(未設定)}"
  echo "TFSTATE_BUCKET : $TFSTATE_BUCKET"
  echo "DB_NAME        : $DB_NAME"
  echo "DB_USER        : $DB_USER"
  echo "DB_PASSWORD    : ${DB_PASSWORD:+(設定済み)}"
}

# bootstrap
cmd_bootstrap() {
  echo "=== GCSバケット作成 ==="
  cd "$ROOT_DIR/terraform/bootstrap"
  terraform init
  terraform apply
}

# Terraform plan/apply/destroy
cmd_terraform() {
  local action=$1
  local env=$2

  if [ -z "$env" ]; then
    echo "ERROR: 環境を指定してください (dev|prod)"
    exit 1
  fi

  cd "$ROOT_DIR/terraform/environments/$env"
  terraform init
  terraform "$action"
}

# Ansible
cmd_ansible() {
  local env=$1
  local tag=$2

  if [ -z "$env" ]; then
    echo "ERROR: 環境を指定してください (dev|prod)"
    exit 1
  fi

  cd "$ROOT_DIR/terraform/ansible"

  local extra_vars="project_id=$GCP_PROJECT_ID"
  extra_vars="$extra_vars prefix=${PROJECT_NAME}-${env}"
  extra_vars="$extra_vars cloudsql_connection_name=${GCP_PROJECT_ID}:${GCP_REGION}:${PROJECT_NAME}-${env}-db"
  extra_vars="$extra_vars db_secret_id=${PROJECT_NAME}-${env}-db-password"
  extra_vars="$extra_vars db_name=$DB_NAME"
  extra_vars="$extra_vars db_user=$DB_USER"

  local cmd="ansible-playbook -i inventory/${env}.yml playbook.yml --extra-vars \"$extra_vars\""

  if [ -n "$tag" ]; then
    cmd="$cmd --tags $tag"
  fi

  eval "$cmd"
}

# メイン
case "${1:-}" in
  info)
    cmd_info
    ;;
  bootstrap)
    cmd_info
    echo ""
    cmd_bootstrap
    ;;
  plan)
    cmd_terraform plan "$2"
    ;;
  apply)
    cmd_terraform apply "$2"
    ;;
  destroy)
    cmd_terraform destroy "$2"
    ;;
  ansible)
    cmd_ansible "$2"
    ;;
  ansible-tag)
    cmd_ansible "$2" "$3"
    ;;
  *)
    usage
    ;;
esac
