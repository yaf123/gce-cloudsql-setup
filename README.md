# GCE + Cloud SQL Setup

GCP上にGCE（Compute Engine）+ Cloud SQL（MySQL）の堅牢なWeb環境を構築するためのTerraform + Ansible構成です。

## 構成図

```
                          Internet
                             │
                    ┌────────▼────────┐
                    │   Cloud Armor   │
                    │  (WAF / DDoS)   │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  External LB    │
                    │  (HTTPS / L7)   │
                    └────────┬────────┘
                             │
  ┌──────────────────────────┼───────────────────────┐
  │  VPC                     │                       │
  │            ┌─────────────▼──────────────┐        │
  │            │  GCE (外部IPなし)           │        │
  │            │  Apache + PHP              │        │
  │            │  Cloud SQL Auth Proxy      │──┐     │
  │            └─────────────┬──────────────┘  │     │
  │                          │ Private IP      │     │
  │            ┌─────────────▼──────────────┐  │     │
  │            │  Cloud SQL (MySQL 8.0)     │  │     │
  │            │  Private IPのみ            │  │     │
  │            └────────────────────────────┘  │     │
  └────────────────────────────────────────────│─────┘
                                               │
                                   Cloud Logging / Monitoring
```

## 特徴

- **外部IPなし**: GCEに外部IPを付与せず、LB経由でのみアクセス可能
- **IAP SSH**: 踏み台サーバー不要、Google認証ベースのSSH接続
- **Private IP接続**: Cloud SQLへはVPC内Private IPのみで接続
- **Secret Manager**: DBパスワードをコードに含めない
- **Cloud Armor**: SQLi / XSS / レート制限によるWAF保護
- **環境分離**: dev / prod を同一コードで管理（変数で切り替え）
- **Ansible構成管理**: GCE内のセットアップをAnsibleで管理（GCE再作成不要で設定変更可能）

## ディレクトリ構成

```
.
├── README.md
├── architecture_*.md                  # 仕様書（全体設計）
├── terraform-guide_*.md               # Terraform入門ガイド
│
└── terraform/
    ├── bootstrap/                     # tfstate用GCSバケット（初回のみ）
    │
    ├── modules/                       # Terraform モジュール
    │   ├── network/                   #   VPC, サブネット, FW, NAT
    │   ├── database/                  #   Cloud SQL, Secret Manager
    │   ├── application/               #   GCE, LB, SSL
    │   └── security/                  #   Cloud Armor
    │
    ├── environments/                  # 環境別設定
    │   ├── dev/                       #   開発環境
    │   └── prod/                      #   本番環境
    │
    └── ansible/                       # GCE内 構成管理
        ├── playbook.yml               #   メインPlaybook
        ├── inventory/                 #   環境別ホスト定義
        ├── group_vars/                #   環境別変数
        └── roles/                     #   ロール
            ├── common/                #     apt, gcloud CLI
            ├── cloud-sql-proxy/       #     Auth Proxy + systemd
            ├── db-config/             #     Secret Manager → DB設定
            ├── apache/                #     Apache + PHP設定
            ├── webapp/                #     PHPアプリデプロイ
            └── ops-agent/             #     Cloud Logging / Monitoring
```

## 前提条件

- GCPプロジェクト（Owner権限）
- ローカル環境（WSL2 / Linux）に以下がインストール済み:
  - [gcloud CLI](https://cloud.google.com/sdk/docs/install)
  - [Terraform](https://developer.hashicorp.com/terraform/install)
  - [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)

## クイックスタート

### 1. 環境変数の設定

```bash
cp .env.example .env
vi .env   # 実際のGCPプロジェクトID等を記入
```

`.env` に記入する主な値:

| 変数 | 説明 | 例 |
|---|---|---|
| `GCP_PROJECT_ID` | GCPプロジェクトID | `my-project-123456` |
| `PROJECT_NAME` | リソース名のプレフィックス | `myapp` |
| `DOMAIN` | ドメイン（HTTPS有効化時） | `example.com` |
| `DB_PASSWORD` | DBパスワード | （任意の強力なパスワード） |
| `GCE_SSH_USER` | GCEへのSSHユーザー名（省略可） | デフォルト: 現在のOSユーザー |
| `GCE_SSH_KEY` | SSH秘密鍵パス（省略可） | デフォルト: `~/.ssh/google_compute_engine` |

> `.env` は `.gitignore` 済みのため、Git管理外です。

### 2. 認証

```bash
gcloud auth login
gcloud auth application-default login
```

### 3. セットアップスクリプトで実行

```bash
# 設定値を確認
./scripts/setup.sh info

# GCSバケット作成（チーム開発時、初回のみ）
./scripts/setup.sh bootstrap      # 確認プロンプトで yes を入力

# dev環境にインフラ構築
./scripts/setup.sh plan dev       # 実行計画確認
./scripts/setup.sh apply dev      # 確認プロンプトで yes を入力

# dev環境にAnsible実行
./scripts/setup.sh ansible dev

# PHPアプリだけ更新
./scripts/setup.sh ansible-tag dev webapp
```

### 4. 動作確認

```bash
# LBの外部IPを確認
cd terraform/environments/dev && terraform output
```

#### IPアドレスで確認（ドメイン不要）

ブラウザで `http://<LBのIP>` にアクセス。

#### ドメインで確認（HTTPS有効化時）

DNS管理サービス（Cloudflare、お名前.com、Route 53 等）で以下のAレコードを設定:

| タイプ | ホスト | 値 | 備考 |
|---|---|---|---|
| A | `@` | LBの外部IP | Cloudflareの場合「DNS only（グレーの雲）」にする |

> **注意:** Cloudflareのプロキシモード（オレンジの雲）を使うと、GCPのSSL証明書の発行・検証が失敗します。必ず「DNS only」に設定してください。

DNS反映後（数分〜最大1時間）、`https://your-domain.com` にアクセスして確認。

### 5. リソース削除

```bash
./scripts/setup.sh destroy dev
```

## Terraform と Ansible の役割分担

| ツール | 担当 | コマンド |
|---|---|---|
| **Terraform** | GCPインフラ（VPC, GCE, Cloud SQL, LB等） | `terraform apply` |
| **Ansible** | GCE内のソフトウェア・設定・アプリデプロイ | `ansible-playbook` |

PHPや設定の変更はAnsibleで差分適用するだけで済み、GCEの再作成は不要です。

```bash
# PHPアプリだけ更新する場合
./scripts/setup.sh ansible-tag dev webapp
```

## 月額コスト目安

| 環境 | 合計 |
|---|---|
| dev | ~$60/月 |
| prod | ~$115/月 |

## ドキュメント

| ファイル | 内容 |
|---|---|
| `architecture_*.md` | 全体仕様書（ネットワーク、DB、LB、Ansible、監視等） |
| `terraform-guide_*.md` | Terraform入門ガイド（コマンド、モジュール構成、トラブルシューティング） |
