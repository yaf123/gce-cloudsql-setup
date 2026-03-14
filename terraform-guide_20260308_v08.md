# Terraform 入門ガイド（GCE + Cloud SQL 構築）

<br>

---

<br>

## 1. Terraformとは

<br>

### 1-1. 一言でいうと

**インフラをコード（テキストファイル）で定義し、コマンド1つで自動構築・変更・削除できるツール。**

<br>

### 1-2. 従来の手作業との比較

| | 手作業（GCPコンソール） | Terraform |
|---|---|---|
| 構築方法 | Webの画面をポチポチ | コードを書いて `terraform apply` |
| 再現性 | 手順書が必要、ミスしやすい | コードが手順書そのもの、何度でも同じ結果 |
| 変更管理 | 「誰がいつ何を変えた」が不明 | gitで差分管理 |
| 環境複製 | 全部やり直し | 変数を変えて `terraform apply` |
| 削除 | リソースを1つずつ消す | `terraform destroy` で全部消える |

<br>

### 1-3. 宣言的 vs 命令的

```
# 命令的（シェルスクリプト）→ 「こうやって作れ」
gcloud compute networks create myapp-vpc ...
gcloud compute networks subnets create myapp-subnet ...
gcloud sql instances create myapp-db ...

# 宣言的（Terraform）→ 「こうなっていてほしい」
resource "google_compute_network" "vpc" {
  name = "myapp-vpc"
}
```

Terraformは「あるべき状態」を書く。現在の状態との差分を自動計算して、足りないものだけ作る。

<br>

---

<br>

## 2. 基本コマンド（4つだけ覚えればOK）

<br>

```
terraform init      # ① 初期化（最初に1回）
terraform plan      # ② 何が変わるか確認（ドライラン）
terraform apply     # ③ 実際に適用（リソース作成・変更）
terraform destroy   # ④ 全リソース削除
```

<br>

### 2-1. terraform init

```bash
$ cd environments/dev    # 環境ディレクトリに移動してから実行
$ terraform init
```

- **最初に1回だけ実行**（環境ごと）
- プロバイダ（GCP用プラグイン）とモジュールをダウンロード
- `.terraform/` ディレクトリが作られる
- `npm install` に相当するイメージ

<br>

### 2-2. terraform plan

```bash
$ terraform plan
```

- **実際には何も変更しない**（確認だけ）
- 「これから何を作る/変える/消すか」を表示
- 表示の見方：
  - `+` 緑 = 新規作成
  - `~` 黄 = 変更
  - `-` 赤 = 削除

```
# 出力例
+ module.network.google_compute_network.vpc will be created
  + name = "myapp-dev-vpc"

Plan: 20 to add, 0 to change, 0 to destroy.
```

<br>

### 2-3. terraform apply

```bash
$ terraform apply
```

- **実際にGCPにリソースを作成する**
- 実行前に plan と同じ内容が表示され `yes` の確認が入る
- 完了後、`terraform.tfstate` に現在の状態が記録される

<br>

### 2-4. terraform destroy

```bash
$ terraform destroy
```

- **Terraformで作った全リソースを削除**
- テスト終了後にこれを実行すれば課金が止まる
- `yes` の確認が入る

<br>

---

<br>

## 3. フォルダ構成の説明（本番運用パターン）

<br>

### 3-1. 全体構成

```
terraform/
├── modules/                           # 再利用可能な「部品」
│   ├── network/                       # ネットワーク層
│   │   ├── main.tf                    #   リソース定義
│   │   ├── variables.tf               #   入力変数
│   │   └── outputs.tf                 #   出力値
│   ├── database/                      # データベース層
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── application/                   # アプリケーション層
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── templates/startup.sh       #   GCE起動スクリプト（最小限）
│   └── security/                      # セキュリティ層
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── bootstrap/                         # tfstate用GCSバケット（初回のみ）
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── outputs.tf
│
├── environments/                      # 環境ごとの設定
│   ├── dev/                           # 開発環境
│   │   ├── main.tf                    #   modulesを呼び出す
│   │   ├── variables.tf               #   変数定義
│   │   ├── terraform.tfvars           #   dev用の値
│   │   ├── outputs.tf                 #   出力値
│   │   ├── .terraform/                #   (自動生成) プラグイン
│   │   ├── .terraform.lock.hcl        #   (自動生成) バージョン固定
│   │   └── terraform.tfstate          #   (自動生成) 状態ファイル ※GCSバックエンド時は不要
│   └── prod/                          # 本番環境
│       ├── main.tf                    #   同じmodulesを呼び出す
│       ├── variables.tf               #   変数定義
│       ├── terraform.tfvars           #   prod用の値
│       └── outputs.tf                 #   出力値
│
└── ansible/                           # 構成管理（GCE内のセットアップ）
    ├── ansible.cfg                    #   IAP SSH接続設定
    ├── playbook.yml                   #   メインPlaybook
    ├── inventory/                     #   環境別ホスト定義
    │   ├── dev.yml
    │   └── prod.yml
    ├── group_vars/                    #   環境別変数
    │   ├── all.yml
    │   ├── dev.yml
    │   └── prod.yml
    └── roles/                         #   ロール（処理の単位）
        ├── common/                    #     apt, gcloud CLI
        ├── cloud-sql-proxy/           #     Proxy + systemd
        ├── db-config/                 #     Secret Manager → DB設定
        ├── apache/                    #     Apache + PHP設定
        ├── webapp/                    #     PHPアプリデプロイ
        └── ops-agent/                 #     Ops Agent設定
```

<br>

### 3-2. modules と environments の関係

```
modules = レシピ（設計図）
environments = 材料（環境ごとの設定値）

    modules/network/          environments/dev/
    ┌──────────────┐         ┌──────────────────┐
    │ VPCを作る     │◀────────│ prefix = dev     │
    │ サブネットを   │  呼び出し │ cidr = 10.0.0.0  │
    │ 作る          │         │                  │
    └──────────────┘         └──────────────────┘
          ▲
          │ 同じレシピを再利用
          │
    ┌──────────────────┐
    │ prefix = prod    │  environments/prod/
    │ cidr = 10.10.0.0 │
    └──────────────────┘
```

- **module**: 「VPCを作る」「Cloud SQLを作る」という処理の定義（何度でも使い回せる）
- **environment**: 「devではこのスペック」「prodではこのスペック」という値だけを変える
- **ansible**: GCE内の構成管理（Apache, PHP, アプリデプロイ等）を担当

**Terraform と Ansible の役割分担:**

| ツール | 担当 | 変更時のコマンド |
|---|---|---|
| **Terraform** | GCPインフラ（VPC, GCE, Cloud SQL, LB等） | `terraform apply` |
| **Ansible** | GCE内のソフトウェア・設定・アプリ | `ansible-playbook` |

> **ポイント:** PHPや設定の変更は Ansible で差分適用するだけで済み、GCEの再作成が不要。startup.sh は最小限（Python確認のみ）に縮小されている。

<br>

### 3-3. 各モジュールの役割

<br>

#### modules/network — ネットワーク層

| リソース | 何をするか | GCPコンソール確認先 |
|---|---|---|
| `google_compute_network` | VPC（仮想ネットワーク）を作る | VPCネットワーク → **VPCネットワーク** |
| `google_compute_subnetwork` | サブネット（IPアドレス範囲）を作る | VPCネットワーク → VPC選択 → **サブネット** |
| `google_compute_firewall` | 通信の許可/拒否ルールを作る | VPCネットワーク → **ファイアウォール** |
| `google_compute_router` | Cloud Routerを作る（NAT用） | ネットワーク接続 → **Cloud Routers** |
| `google_compute_router_nat` | Cloud NATを作る（外部通信用） | ネットワークサービス → **Cloud NAT** |
| `google_compute_global_address` | Cloud SQL用Private IP範囲確保 | VPCネットワーク → VPC選択 → **プライベートサービス接続** |
| `google_service_networking_connection` | VPCとCloud SQLをPrivate接続 | VPCネットワーク → VPC選択 → **プライベートサービス接続** |

<br>

#### modules/database — データベース層

| リソース | 何をするか | GCPコンソール確認先 |
|---|---|---|
| `google_sql_database_instance` | Cloud SQLインスタンス作成（HA, バックアップ等） | **SQL** → インスタンス一覧 |
| `google_sql_database` | データベース作成 | **SQL** → インスタンス → **データベース** タブ |
| `google_sql_user` | データベースユーザー作成 | **SQL** → インスタンス → **ユーザー** タブ |
| `google_secret_manager_secret` | Secret Manager（パスワード保管） | セキュリティ → **Secret Manager** |

<br>

#### modules/application — アプリケーション層

| リソース | 何をするか | GCPコンソール確認先 |
|---|---|---|
| `google_service_account` | GCE用のサービスアカウント作成 | IAMと管理 → **サービスアカウント** |
| `google_project_iam_member` | 権限を付与（Cloud SQL, Secret Manager等） | IAMと管理 → **IAM** |
| `google_compute_instance` | GCE作成 + 起動スクリプト（最小限） | Compute Engine → **VMインスタンス** |
| `google_compute_global_address` | LB用の外部IPアドレス取得 | VPCネットワーク → **IPアドレス** |
| `google_compute_instance_group` | GCEをグループにまとめる（lifecycle連動） | Compute Engine → **インスタンスグループ** |
| `google_compute_health_check` | サーバー死活監視 | Compute Engine → **ヘルスチェック** |
| `google_compute_backend_service` | バックエンド定義 | ネットワークサービス → **ロードバランシング** → **バックエンド** |
| `google_compute_url_map` | URLルーティング | ネットワークサービス → **ロードバランシング** |
| `google_compute_target_http(s)_proxy` | HTTP(S)プロキシ | ネットワークサービス → **ロードバランシング** → LB選択 |
| `google_compute_global_forwarding_rule` | IPとプロキシを紐付け | ネットワークサービス → **ロードバランシング** → **フロントエンド** |
| `google_compute_managed_ssl_certificate` | SSL証明書（ドメインあり時） | ネットワークサービス → ロードバランシング → **証明書** |

<br>

#### modules/security — セキュリティ層

> **GCPコンソール確認先:** ネットワークセキュリティ → **Cloud Armor ポリシー**

| ルール | 何をするか |
|---|---|
| SQLi防御 | SQLインジェクション攻撃をブロック |
| XSS防御 | クロスサイトスクリプティングをブロック |
| レート制限 | 1IPあたりN req/minを超えたら拒否 |

<br>

### 3-4. 環境（dev / prod）の出力値

```
apply完了後に表示される値:
- LBの外部IPアドレス（ブラウザでアクセスする先）
- GCEの内部IP
- Cloud SQLのPrivate IP
- Cloud SQL接続名（Auth Proxy用）
- SSH接続コマンド
```

<br>

### 3-5. 環境ごとの設定差分

| 設定 | dev | prod |
|---|---|---|
| リソース名プレフィックス | `myapp-dev-*` | `myapp-prod-*` |
| Cloud SQL マシンタイプ | db-f1-micro | db-g1-small |
| Cloud SQL HA | 無効 | 有効 |
| Cloud SQL 削除保護 | 無効 | 有効 |
| バックアップ保持 | 7日 | 30日 |
| GCE マシンタイプ | e2-small | e2-medium |
| フローログ | 50%サンプリング | 全量 |
| レート制限 | 100 req/min | 200 req/min |
| サブネットCIDR | 10.0.0.0/24 | 10.10.0.0/24 |

<br>

---

<br>

## 4. 構築の流れ（全体像）

<br>

```
[Step 1] コードを書く（完了済み）
    │
    ▼
[Step 1.5] GCSバックエンド作成（チーム開発時、初回のみ）
    │    cd bootstrap
    │    terraform init && terraform apply
    │    → environments/dev,prod の backend "gcs" コメントを外す
    │
    ▼
[Step 2] dev環境で初期化
    │    cd environments/dev
    │    terraform init
    │
    ▼
[Step 3] dev環境で確認
    │    terraform plan
    │    「20リソース作ります」と表示される
    │
    ▼
[Step 4] dev環境で適用
    │    terraform apply
    │    DBパスワードを入力 → yes で実行
    │    ⏱ 約10〜15分かかる（Cloud SQLが遅い）
    │
    ▼
[Step 5] Ansible でGCE内セットアップ
    │    cd ../../ansible
    │    ansible-playbook -i inventory/dev.yml playbook.yml
    │    ⏱ 約5分（パッケージインストール + 設定）
    │
    ▼
[Step 6] 動作確認
    │    ├─ LBのIPでブラウザアクセス → デモアプリ表示
    │    ├─ IAP経由でSSH接続
    │    └─ GCE内からCloud SQL接続確認
    │
    ▼
[Step 7] devで問題なければprodにも適用
    │    cd ../environments/prod
    │    terraform init && terraform plan && terraform apply
    │    cd ../../ansible
    │    ansible-playbook -i inventory/prod.yml playbook.yml
    │
    ▼
[Step 8] テスト終了後
         cd environments/dev && terraform destroy  ← dev削除
         cd ../prod && terraform destroy            ← prod削除
```

<br>

---

<br>

## 5. 重要な概念

<br>

### 5-1. State（状態ファイル）

```
terraform.tfstate
```

- Terraformが「今GCPに何があるか」を記録するファイル
- **これを消すとTerraformがリソースを見失う**（GCPには残るがTerraformから管理できなくなる）
- 環境ごとに別々のstateファイルを持つ（dev/prodが独立）
- チーム開発ではGCSバックエンドに保存する（下記参照）

<br>

### 5-2. リモートバックエンド（チーム開発向け）

チーム開発では tfstate をGCSバケットに保存し、全員が同じ状態を参照する。

```
Aさんのpc ──┐
            ├──→ GCSバケット (tfstate) ──→ GCP
Bさんのpc ──┘    + ロック機能
```

**Step 1: GCSバケット作成（bootstrap、初回のみ）**

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

GCSバケット `myapp-terraform-state` が作成される。バケットの設定:

| 設定 | 値 | 理由 |
|---|---|---|
| バージョニング | 有効 | tfstate の履歴保持・復元 |
| 均一バケットレベルアクセス | 有効 | セキュリティ推奨 |
| ライフサイクル | 古いバージョン10世代で削除 | コスト管理 |
| 誤削除防止 | `force_destroy = false` | 安全性 |

**Step 2: backend 有効化（environments/dev, prod）**

`environments/dev/main.tf` のコメントを外す:

```hcl
terraform {
  backend "gcs" {
    bucket = "myapp-terraform-state"
    prefix = "dev"                      # 環境ごとにprefixを分ける
  }
}
```

```bash
terraform init    # ローカルのtfstateをGCSに移行するか聞かれる → yes
```

**Step 3: チームメンバーの利用**

```bash
terraform init    # GCSからtfstateを自動取得
terraform plan    # 最新の状態との差分を確認
terraform apply   # 適用 → GCSのtfstateを自動更新
```

| 機能 | 説明 |
|---|---|
| 共有 | 全員が同じ tfstate を参照 |
| ロック | 誰かが apply 中は他の人が apply できない（競合防止） |
| バージョニング | GCSで履歴保持、誤操作時に復元可能 |
| 暗号化 | GCSのサーバーサイド暗号化で保護 |

> **注意:** bootstrap 自体の tfstate はローカル管理（bootstrap は1回しか実行しないため）。

<br>

### 5-3. Module（モジュール）

```hcl
# environments/dev/main.tf から modules/network を呼び出す
module "network" {
  source = "../../modules/network"    # モジュールの場所

  prefix = "myapp-dev"               # 変数を渡す
  region = "asia-northeast1"
}

# モジュールの出力値を別のモジュールに渡す
module "database" {
  source = "../../modules/database"

  vpc_id = module.network.vpc_id      # network の出力 → database の入力
}
```

- `source`: モジュールのパス（ローカルまたはレジストリ）
- モジュール間のデータは `output` → `variable` で受け渡し
- 同じモジュールを dev/prod で使い回すことで、環境差異を防ぐ

<br>

### 5-4. リソースの依存関係

```hcl
# Terraformは依存関係を自動解決する
module "database" {
  vpc_id = module.network.vpc_id   # ← networkが先に作られる
}
```

- 参照関係から順序を自動判断
- 並列で作れるものは並列で作る（だから速い）
- 明示が必要な場合は `depends_on` を使う

<br>

### 5-5. sensitive（機密情報）

```hcl
variable "db_password" {
  sensitive = true   # plan/applyの出力でマスクされる
}
```

- `terraform plan` の出力に `(sensitive value)` と表示
- ログにパスワードが残らない

<br>

### 5-6. templatefile / file（外部ファイル読み込み）

```hcl
# 変数埋め込みが必要な場合
metadata_startup_script = templatefile("${path.module}/templates/startup.sh", {
  cloudsql_connection_name = var.cloudsql_connection_name
})

# 変数不要な場合（現在のstartup.shはこちら）
metadata_startup_script = file("${path.module}/templates/startup.sh")
```

- `templatefile`: 外部ファイルにTerraformの変数を埋め込む（`${変数名}` で置換）
- `file`: 外部ファイルをそのまま読み込む（変数不要の場合）
- 現在のstartup.shは最小限（Python確認のみ）のため `file()` を使用
- GCE内のソフトウェア設定はAnsibleで管理するため、startup.shに変数を渡す必要がない

<br>

---

<br>

## 6. よく使う補助コマンド

<br>

| コマンド | 用途 |
|---|---|
| `terraform fmt` | コードを整形（インデント等） |
| `terraform validate` | 構文チェック（APIは呼ばない） |
| `terraform state list` | 管理中のリソース一覧 |
| `terraform state show <リソース>` | リソースの詳細表示 |
| `terraform output` | 出力値を再表示 |
| `terraform plan -target=<リソース>` | 特定リソースだけplanする |

<br>

---

<br>

## 7. フォルダ構成パターン比較

<br>

| パターン | 構成 | 向いている場面 |
|---|---|---|
| フラット | 1フォルダに全.tf | 学習・小規模テスト |
| レイヤー分割 | network/ database/ app/ | 1環境でレイヤー単位管理 |
| **modules + environments（今回）** | modules/ + environments/dev,prod/ | **本番運用・複数環境** |

今回の構成は「同じ設計で dev/prod を管理し、環境差はtfvarsで吸収」する本番運用パターン。

<br>

---

<br>

## 8. GCPコンソールでの確認ページ一覧

<br>

Terraformで作成したリソースは、GCPコンソールで状態・使用率・ログを確認できる。

<br>

### 8-1. リソース使用率の確認

| 確認対象 | GCPコンソールメニュー | 見られるグラフ |
|---|---|---|
| GCE CPU/メモリ/ディスク | Compute Engine → VMインスタンス → VM選択 → **モニタリング** | CPU使用率、ネットワーク送受信、ディスクI/O |
| Cloud SQL 負荷 | SQL → インスタンス選択 → **モニタリング** | CPU、メモリ、接続数、クエリ数、ストレージ |
| LB トラフィック | ネットワークサービス → ロードバランシング → LB選択 → **モニタリング** | RPS、エラー率、レイテンシ |
| 全体ダッシュボード | Monitoring → **ダッシュボード** | GCE/Cloud SQL等の一覧グラフ |
| 任意メトリクス検索 | Monitoring → **Metrics Explorer** | 自由にメトリクスを選んでグラフ化 |

<br>

### 8-2. ログの確認

| 確認対象 | GCPコンソールメニュー | フィルタ方法 |
|---|---|---|
| Apache アクセスログ | Logging → **Logs Explorer** | リソース: `GCE Instance` → ログ名: `apache_access` |
| Apache エラーログ | Logging → **Logs Explorer** | リソース: `GCE Instance` → ログ名: `apache_error` |
| PHP エラーログ | Logging → **Logs Explorer** | `labels.app="php"` |
| Cloud SQL ログ | Logging → **Logs Explorer** | リソース: `Cloud SQL Database` |
| LB リクエストログ | Logging → **Logs Explorer** | リソース: `HTTP Load Balancer` |
| Cloud Armor ブロックログ | Logging → **Logs Explorer** | `jsonPayload.enforcedSecurityPolicy.outcome="DENY"` |
| SSH接続記録 | Logging → **Logs Explorer** | リソース: `GCE Instance` → ログ名: `authlog` |

<br>

### 8-3. アラート設定

| 操作 | GCPコンソールメニュー |
|---|---|
| アラートポリシー作成 | Monitoring → **アラート** → **ポリシーを作成** |
| 通知先設定（メール等） | Monitoring → **アラート** → **通知チャンネルを編集** |
| 発生中インシデント確認 | Monitoring → **アラート** → **インシデント** |

<br>

---

<br>

## 9. HTTPS / ドメイン設定

<br>

### 9-1. ドメインなし（デフォルト）

```hcl
# terraform.tfvars — domainを設定しない or 空文字
# → HTTP (ポート80) のみでアクセス
```

<br>

### 9-2. HTTPS有効化

```hcl
# terraform.tfvars にドメインを追加
domain = "example.com"
```

```bash
terraform plan -var="db_password=xxx"    # 7リソース追加を確認
terraform apply -var="db_password=xxx"   # 適用
```

**作成されるリソース:**
- Google Managed SSL証明書（無料、自動発行・自動更新）
- HTTPS Proxy + Forwarding Rule (443)
- HTTP→HTTPS リダイレクト URL Map

<br>

### 9-3. SSL証明書のプロビジョニング

> **GCPコンソール確認先:** ネットワークサービス → **ロードバランシング** → 左メニュー **証明書** → `myapp-dev-cert`

apply後、SSL証明書が有効になるまで **15〜30分** かかる。

```bash
# 状態確認
gcloud compute ssl-certificates describe myapp-dev-cert \
  --global --format="value(managed.status,managed.domainStatus)"

# PROVISIONING → 発行中（待つ）
# ACTIVE       → 完了！ https://example.com/ でアクセス可能
```

**前提条件:** DNSのAレコードがLBのIPに向いていること。

<br>

### 9-4. DNS設定（Cloudflare利用時の注意）

| 設定 | 値 |
|---|---|
| タイプ | A |
| 名前 | `@` |
| IPv4 | LBのIPアドレス |
| プロキシ状態 | **DNS only（グレーの雲）** |

- **Proxied（オレンジの雲）にするとSSL証明書が発行されない**
- GoogleがドメインのIP確認をできなくなるため

<br>

---

<br>

## 10. トラブルシューティング

<br>

### 10-1. LBが503を返す（バックエンドが空）

**症状:** `https://example.com/` にアクセスすると503エラー。GCE自体は稼働中。

**原因:** Unmanaged Instance GroupからGCEインスタンスが外れている。

GCPの仕様で、GCEが停止・削除・再作成されるとIGメンバーシップが自動解除される。

**確認方法:**

```bash
# IGのメンバーが空か確認
gcloud compute instance-groups list-instances {prefix}-ig \
  --zone=asia-northeast1-a

# バックエンドのヘルス確認
gcloud compute backend-services get-health {prefix}-backend --global
```

**復旧方法:**

```bash
# 方法1: terraform apply で自動修復（推奨）
cd environments/dev
terraform apply -var="db_password=xxx"

# 方法2: 手動で即時復旧
gcloud compute instance-groups unmanaged add-instances {prefix}-ig \
  --zone=asia-northeast1-a \
  --instances={prefix}-web
```

**恒久対策（適用済み）:**

Terraformの `replace_triggered_by` により、GCE再作成時にIGも自動再作成される。

```hcl
resource "google_compute_instance_group" "web" {
  instances = [google_compute_instance.web.self_link]

  lifecycle {
    replace_triggered_by = [google_compute_instance.web.id]
  }
}
```

<br>

### 10-2. SSL証明書がPROVISIONINGのまま

**症状:** HTTPS接続不可。証明書ステータスが `PROVISIONING`。

**確認方法:**

```bash
gcloud compute ssl-certificates describe {prefix}-cert \
  --global --format="value(managed.status,managed.domainStatus)"
```

**対処:**
- DNS AレコードがLBのIPに向いているか確認
- Cloudflareの場合、プロキシ状態を **DNS only（グレーの雲）** にする
- 15〜30分待つ（最大数時間かかることもある）

<br>

### 10-3. terraform plan で差分が出る（変更していないのに）

**症状:** `db_password` 関連で差分が出る。

**原因:** `-var="db_password=xxx"` に正しいパスワードを渡していない。

**対処:**

```bash
# Secret Managerから現在のパスワードを取得して使用
REAL_PW=$(gcloud secrets versions access latest \
  --secret={prefix}-db-password --project=<PROJECT_ID>)
terraform plan -var="db_password=${REAL_PW}"
```

<br>

### 10-4. terraform destroy が1回で完了しない（VPCピアリング削除エラー）

**症状:** `terraform destroy` 実行時に以下のエラーで失敗する。

```
Error: Unable to remove Service Networking Connection, err: Failed to delete connection;
Producer services (e.g. CloudSQL, Cloud Memstore, etc.) are still using this connection.
```

**原因:** Cloud SQLインスタンスの削除後、GCP内部のクリーンアップに数分かかる。Terraformは Cloud SQL 削除直後にVPCピアリング接続（`google_service_networking_connection`）の削除を試みるが、GCP側で「まだ使用中」と判定されて失敗する。

**対処:**

```bash
# 1. Cloud SQLが完全に削除されたか確認
gcloud sql instances list --project=<PROJECT_ID>

# 2. VPCピアリング接続をstateから除外
terraform state rm module.network.google_service_networking_connection.private_vpc_connection

# 3. 残りのリソースを削除
terraform destroy -var="db_password=xxx" -auto-approve
```

> **補足:** stateから除外したVPCピアリング接続は、Cloud SQLのクリーンアップ完了後にGCP側で自動的に解放される。手動削除は不要。

<br>

### 10-5. terraform.tfvars のプレースホルダ値が使われる

**症状:** `setup.sh` 経由で実行しているのに、`terraform plan` で `project = "your-gcp-project-id"` 等のプレースホルダ値が表示される。

**原因:** `terraform.tfvars` にプレースホルダ値がハードコードされている。

**対処:** 共通設定（`project_id`, `project_name`, `region`, `zone`, `domain`）は `terraform.tfvars` から削除する。これらは `.env` → `setup.sh` → `TF_VAR_` 環境変数で注入される。`terraform.tfvars` には環境固有の設定（`env`, `db_tier`, `ha_enabled`, `machine_type`）のみ残す。

> **補足:** Terraformの変数優先順位: `TF_VAR_` 環境変数 > `terraform.tfvars` > `variables.tf` の default。`TF_VAR_` が最も優先されるが、tfvarsにプレースホルダが残っていると plan 表示時に紛らわしい。

<br>

### 10-6. WSL2: スクリプトが実行できない（CRLF改行）

**症状:**

```
bash: ./scripts/setup.sh: cannot execute: required file not found
```

**原因:** WSL2のWindowsマウント（`/mnt/d/` 等）上で作成・編集されたファイルはCRLF改行になることがある。bashはshebang行（`#!/bin/bash\r`）を解釈できずエラーになる。

**確認方法:**

```bash
file scripts/setup.sh
# → "with CRLF line terminators" と表示されたらNG
```

**対処:**

```bash
# LFに変換（sed -i はWSL2のWindowsマウントで効かない場合があるため tr を使用）
tr -d '\r' < scripts/setup.sh > /tmp/setup.sh && cp /tmp/setup.sh scripts/setup.sh
tr -d '\r' < .env > /tmp/dotenv && cp /tmp/dotenv .env
```

<br>

### 10-7. Ansible: ansible.cfg が無視される（world writable directory）

**症状:**

```
[WARNING]: Ansible is being run in a world writable directory, ignoring it as an ansible.cfg source.
```

**原因:** WSL2のWindowsマウント上のディレクトリは `777` パーミッション（world writable）となる。Ansibleはセキュリティ上、world writable なディレクトリの `ansible.cfg` を無視する。

**対処:** `setup.sh` では `ansible.cfg` を使わず、環境変数（`ANSIBLE_REMOTE_USER`, `ANSIBLE_SSH_ARGS` 等）で設定を注入しているため、追加対処は不要。

<br>

### 10-8. Ansible: Permission denied (publickey)

**症状:**

```
fj6600ee_gmail_com@rubese-dev-web: Permission denied (publickey).
```

**原因:** SSHユーザー名またはSSH鍵が正しくない。

| 確認ポイント | 対処 |
|---|---|
| SSH鍵が未生成 | `gcloud compute ssh <インスタンス名> --zone=<ゾーン> --tunnel-through-iap` を1回実行 |
| ユーザー名の不一致 | `gcloud compute ssh` 接続時のプロンプト（`ユーザー名@ホスト:~$`）を確認し `.env` の `GCE_SSH_USER` に設定 |
| SSH鍵パスの不一致 | `.env` の `GCE_SSH_KEY` に正しい秘密鍵パスを設定 |

> **注意:** OS Loginのユーザー名（`gcloud compute os-login describe-profile` で取得する `email_com` 形式）と、実際のGCE上のSSHユーザー名は異なる場合がある。`gcloud compute ssh` で接続した際に表示されるユーザー名が正しい。

<br>

### 10-9. Ansible `--tags` でタスクが実行されない

**症状:** `setup.sh ansible-tag dev webapp` を実行しても `Gathering Facts` のみで終了し、対象ロールのタスクが実行されない。

**原因:** `playbook.yml` のロール定義にタグが付いていない。

**対処:** ロール定義にタグを付与する。

```yaml
# NG: タグなし
roles:
  - webapp

# OK: タグあり
roles:
  - { role: webapp, tags: ['webapp'] }
```

<br>

### 10-10. Ops Agent 起動失敗（設定ファイルエラー）

**症状:** Ansible の `restart ops-agent` ハンドラで失敗。

```
Unable to restart service google-cloud-ops-agent
```

**原因の確認:**

```bash
gcloud compute ssh <インスタンス名> --zone=<ゾーン> --tunnel-through-iap \
  -- "sudo journalctl -xeu google-cloud-ops-agent --no-pager | tail -30"
```

**よくある原因:**

| 原因 | 対処 |
|---|---|
| `filter_pattern` は `files` レシーバーの有効なオプションではない | `filter_pattern` 行を削除し、syslog パイプラインに統合 |
| YAML構文エラー | `config.yaml.j2` のインデントを確認 |
| ログファイルが存在しない | `include_paths` で指定したファイルが存在するか確認 |

<br>

### 10-11. Ansible テンプレートファイルが見つからない

**症状:**

```
Could not find or access 'myapp-db.conf.j2'
```

**原因:** タスクの `src:` で指定したテンプレートファイル名と、`templates/` ディレクトリ内の実際のファイル名が一致していない。プロジェクト名の汎用化（sanitize）時にタスク側のみ変更してテンプレートファイル名が旧名のまま残るケースで発生する。

**対処:** テンプレートファイル名をプロジェクト名に依存しない汎用名にリネームし、タスクの `src:` も合わせる。

```yaml
# NG: プロジェクト固有名
src: rubese-db.conf.j2

# OK: 汎用名
src: db.conf.j2
```

<br>

### 10-12. LB IPで ERR_CONNECTION_CLOSED

**症状:** ブラウザで `http://<LBのIP>` にアクセスすると `ERR_CONNECTION_CLOSED`。

**原因:** `domain` が設定されていると、HTTP (80) はHTTPSリダイレクト専用になり、HTTPS (443) はSSL証明書が未発行（PROVISIONING）のため接続が閉じられる。

**対処:** DNS Aレコード設定前はHTTPリダイレクトを無効化する。本構成ではHTTP直接アクセスを常時有効にし、ドメイン設定時はHTTP + HTTPSの並行運用としている。

<br>

### 10-13. DB接続で Access denied（DB名/ユーザー名の不一致）

**症状:** PHPの `db-check.php` でDB接続エラー。

```
Access denied for user 'rubese-app'@'cloudsqlproxy~10.0.0.2' to database 'rubese'
```

**原因:** `terraform/environments/dev/main.tf` のモジュール呼び出しにDB名・ユーザー名がハードコードされていた（`"myapp"`, `"myapp-app"`）。`.env` で `DB_NAME=rubese` としても反映されない。

**対処:** ハードコードを `var.db_name` / `var.db_user` に変更し、`setup.sh` から `TF_VAR_db_name` / `TF_VAR_db_user` としてエクスポートする。

```hcl
# NG: ハードコード
db_name = "myapp"

# OK: 変数化
db_name = var.db_name
```

<br>

### 10-14. terraform apply で database exists エラー

**症状:**

```
Error creating Database: googleapi: Error 400: Can't create database 'rubese'; database exists.
```

**原因:** `gcloud sql databases create` で手動作成したDBが既に存在しており、Terraformの管理外となっている。

**対処:** `terraform import` で既存リソースをstateに取り込む。

```bash
terraform import module.database.google_sql_database.default \
  "projects/<PROJECT_ID>/instances/<INSTANCE_NAME>/databases/<DB_NAME>"
```

> **教訓:** Terraform管理下のリソースを `gcloud` コマンドで手動作成すると、state との不整合が発生する。手動作成した場合は必ず `terraform import` でstateに取り込む。

<br>

### 10-15. forwarding rule の IP address in-use エラー

**症状:**

```
Error creating GlobalForwardingRule: Specified IP address is in-use and would result in a conflict.
```

**原因:** 同一IPアドレスで旧forwarding rule（HTTPリダイレクト）の削除と新forwarding rule（HTTP直接）の作成が同時に実行され、IPアドレスが競合した。

**対処:** 再度 `terraform apply` を実行すれば解消する。旧ルールは前回で削除済みのため、新ルールの作成のみ実行される。

<br>

---

<br>

## 11. 次のステップ

```bash
# ① dev環境で初期化・確認
cd .claude/tmp/gce-cloudsql-setup/terraform/environments/dev
terraform init      # 完了済み
terraform plan      # 何が作られるか確認

# ② dev環境で適用（ユーザー確認後）
terraform apply

# ③ Ansible でGCE内セットアップ
cd ../../ansible
ansible-playbook -i inventory/dev.yml playbook.yml

# ④ HTTPS有効化（ドメイン取得後）
cd ../environments/dev
# terraform.tfvars に domain = "example.com" を追加
terraform apply

# ⑤ PHPアプリ変更時（GCE再作成不要）
cd ../../ansible
ansible-playbook -i inventory/dev.yml playbook.yml --tags webapp

# ⑥ テスト終了後（全削除）
cd ../environments/dev
terraform destroy
```
