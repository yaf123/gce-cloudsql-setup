# GCE + Cloud SQL 堅牢構成 仕様書

<br>

## 1. 全体構成図

```
                        ┌─────────────────────────────────────────────┐
                        │                 Internet                    │
                        └────────────────────┬────────────────────────┘
                                             │
                                   ┌─────────▼─────────┐
                                   │    Cloud Armor     │
                                   │  (WAF / DDoS防御)  │
                                   └─────────┬─────────┘
                                             │
                                   ┌─────────▼─────────┐
                                   │  External App LB   │
                                   │   (HTTPS / L7)     │
                                   │  Anycast Global IP  │
                                   └─────────┬─────────┘
                                             │
 ┌───────────────────────────────────────────┼──────────────────────────────┐
 │  VPC: {prefix}-vpc                        │                              │
 │  ┌───────────────────────────────────────┼────────────────────────┐     │
 │  │  Subnet: {prefix}-subnet              │                        │     │
 │  │  asia-northeast1                      │                        │     │
 │  │  Private Google Access: ON             │                        │     │
 │  │                              ┌─────────▼─────────┐             │     │
 │  │                              │       GCE          │             │     │
 │  │           ┌──IAP SSH────────▶│  {prefix}-web      │             │     │
 │  │           │                  │  外部IPなし         │             │     │
 │  │           │                  │  Apache + PHP      │             │     │
 │  │           │                  │  Cloud SQL Proxy   │──┐          │     │
 │  │           │                  │  Ops Agent         │  │          │     │
 │  │           │                  └─────────┬─────────┘  │          │     │
 │  │           │                            │ Private IP │          │     │
 │  │           │                  ┌─────────▼─────────┐  │          │     │
 │  │           │                  │  Private Services  │  │          │     │
 │  │           │                  │  Access (Peering)  │  │          │     │
 │  │           │                  └─────────┬─────────┘  │          │     │
 │  └───────────│────────────────────────────┼────────────│──────────┘     │
 │              │                  ┌─────────▼─────────┐  │                │
 │              │                  │    Cloud SQL       │  │                │
 │              │                  │    MySQL 8.0       │  │                │
 │              │                  │    {prefix}-db     │  │                │
 │              │                  │    Private IPのみ   │  │                │
 │              │                  └───────────────────┘  │                │
 │              │                                         │                │
 │  ┌───────────┼────────────────────────────────────┐    │                │
 │  │  Cloud Router + Cloud NAT                      │    │                │
 │  │  GCE → 外部通信 (apt, pip等)                    │    │                │
 │  └────────────────────────────────────────────────┘    │                │
 └────────────────────────────────────────────────────────│────────────────┘
                                                          │
                                              ┌───────────▼───────────┐
                                              │  Cloud Logging        │
                                              │  + Cloud Monitoring   │
                                              │  (ログ検索・メトリクス   │
                                              │   ダッシュボード・アラート) │
                                              └───────────────────────┘
 ┌──────────────────────┐
 │  管理者PC             │
 │  gcloud CLI           │──── IAP Tunnel ──── GCE SSH
 └──────────────────────┘
```

**{prefix}** は環境ごとに異なる: `myapp-dev` / `myapp-prod`

<br>

---

<br>

## 2. 環境分離設計

<br>

### 2-1. Terraform + Ansible 構成

```
terraform/
├── bootstrap/                  # tfstate用GCSバケット作成（初回のみ）
├── modules/                    # 再利用可能な部品（設計図）
│   ├── network/                #   ネットワーク層
│   ├── database/               #   データベース層
│   ├── application/            #   アプリケーション層（GCE + LB）
│   └── security/               #   セキュリティ層（Cloud Armor）
├── environments/               # 環境ごとの設定値
│   ├── dev/                    #   開発環境
│   └── prod/                   #   本番環境
└── ansible/                    # 構成管理（Ansible）
    ├── inventory/              #   環境別ホスト定義
    ├── group_vars/             #   環境別変数
    ├── playbook.yml            #   メインPlaybook
    └── roles/                  #   ロール（common, apache, webapp等）
```

**役割分担:**

| ツール | 責務 |
|---|---|
| **Terraform** | GCPインフラ構築（VPC, GCE, Cloud SQL, LB等） |
| **Ansible** | GCE内の構成管理（Apache, PHP, アプリデプロイ, Ops Agent等） |

<br>

### 2-2. 環境別スペック一覧

| 設定 | dev | prod |
|---|---|---|
| リソース名プレフィックス | `myapp-dev-*` | `myapp-prod-*` |
| サブネットCIDR | 10.0.0.0/24 | 10.10.0.0/24 |
| Private Services CIDR | 10.1.0.0 | 10.11.0.0 |
| GCE マシンタイプ | e2-small (2vCPU, 2GB) | e2-medium (2vCPU, 4GB) |
| Cloud SQL マシンタイプ | db-f1-micro (0.6GB) | db-g1-small (1.7GB) |
| Cloud SQL HA | 無効 | 有効 |
| Cloud SQL 削除保護 | 無効 | 有効 |
| バックアップ保持 | 7日 | 30日 |
| フローログ | 50%サンプリング | 全量 |
| レート制限 | 100 req/min | 200 req/min |

<br>

### 2-3. 月額コスト比較

| リソース | dev | prod |
|---|---|---|
| GCE | ~$15 (e2-small) | ~$25 (e2-medium) |
| Cloud SQL | ~$10 (micro, HA無) | ~$50 (small, HA有) |
| External LB | ~$20 | ~$20 |
| Cloud NAT | ~$5 | ~$5 |
| Cloud Armor | ~$5 | ~$5 |
| ストレージ | ~$5 | ~$10 |
| **合計** | **~$60/月** | **~$115/月** |

<br>

---

<br>

## 3. ネットワーク構成（modules/network）

<br>

### 3-1. VPC

| 項目 | 値 |
|---|---|
| 名前 | `{prefix}-vpc` |
| モード | カスタム |
| スコープ | グローバル（GCP標準） |
| 備考 | デフォルトVPCは使用しない（セキュリティ・管理性のため） |

> **GCPコンソール確認先:** VPCネットワーク → **VPCネットワーク** → `{prefix}-vpc` を選択

<br>

### 3-2. サブネット

| 項目 | dev | prod |
|---|---|---|
| 名前 | `myapp-dev-subnet` | `myapp-prod-subnet` |
| リージョン | asia-northeast1（東京） | asia-northeast1（東京） |
| CIDR | 10.0.0.0/24 | 10.10.0.0/24 |
| Private Google Access | 有効 | 有効 |
| フローログ | 50%サンプリング | 全量（100%） |

> **GCPコンソール確認先:** VPCネットワーク → **VPCネットワーク** → `{prefix}-vpc` → **サブネット** タブ → `{prefix}-subnet`

**Private Google Access を有効化する理由:**

- 外部IPを持たないGCEからGoogle APIやサービス（Cloud SQL, Cloud Storage等）にアクセス可能にする
- Cloud NAT経由の通信を減らし、コスト削減とレイテンシ改善

<br>

### 3-3. ファイアウォールルール

| ルール名 | 方向 | ソース | ターゲット | ポート | 用途 |
|---|---|---|---|---|---|
| `{prefix}-allow-iap-ssh` | Ingress | 35.235.240.0/20 (IAP) | タグ: `web` | TCP 22 | IAP経由SSH |
| `{prefix}-allow-lb-to-web` | Ingress | 130.211.0.0/22, 35.191.0.0/16 | タグ: `web` | TCP 80, 443 | LBからWeb + ヘルスチェック |
| `{prefix}-deny-all-ingress` | Ingress | 0.0.0.0/0 | 全て | 全て | デフォルト拒否（優先度最低） |

> **GCPコンソール確認先:** VPCネットワーク → **ファイアウォール** → ルール名で検索

**設計方針:**

- デフォルト拒否 + 必要な通信のみ許可（ホワイトリスト方式）
- IAP経由のSSHのみ許可（踏み台サーバー不要、ポート22を外部公開しない）
- LBのソースIPレンジはGoogleの公式ドキュメントに基づく固定値

<br>

### 3-4. Cloud Router + Cloud NAT

| 項目 | 値 |
|---|---|
| Router名 | `{prefix}-router` |
| NAT名 | `{prefix}-nat` |
| リージョン | asia-northeast1 |
| 対象 | サブネット内の全インスタンス |
| IPアドレス割り当て | 自動 |

> **GCPコンソール確認先:**
> - Cloud Router: ネットワーク接続 → **Cloud Routers** → `{prefix}-router`
> - Cloud NAT: ネットワークサービス → **Cloud NAT** → `{prefix}-nat`

**Cloud NATが必要な理由:**

- GCEに外部IPを付与しないため、そのままでは `apt update` 等ができない
- Cloud NATはリージョン単位で自動HAなので、AWSのNAT Gatewayより運用が楽

<br>

### 3-5. Private Services Access

| 項目 | dev | prod |
|---|---|---|
| IP範囲名 | `myapp-dev-google-managed-services` | `myapp-prod-google-managed-services` |
| CIDR | 10.1.0.0/24 | 10.11.0.0/24 |
| ピアリング先 | `servicenetworking.googleapis.com` | `servicenetworking.googleapis.com` |

> **GCPコンソール確認先:** VPCネットワーク → **VPCネットワーク** → `{prefix}-vpc` → **プライベートサービス接続** タブ

**Private Services Access とは:**

- GCPのマネージドサービス（Cloud SQL等）にVPC内からPrivate IPでアクセスするための仕組み
- VPCピアリングを使ってGoogleの内部ネットワークと接続
- Cloud SQLに外部IPを付与する必要がなくなり、セキュリティが向上

<br>

---

<br>

## 4. Cloud SQL 構成（modules/database）

<br>

### 4-1. インスタンス仕様

> **GCPコンソール確認先:** **SQL** → インスタンス一覧 → `{prefix}-db` を選択

| 項目 | dev | prod |
|---|---|---|
| 名前 | `myapp-dev-db` | `myapp-prod-db` |
| データベースエンジン | MySQL 8.0 | MySQL 8.0 |
| マシンタイプ | db-f1-micro (0.6GB) | db-g1-small (1.7GB) |
| 高可用性 | 無効 | 有効（リージョナル） |
| ストレージ | SSD 10GB（自動拡張有効） | SSD 10GB（自動拡張有効） |
| 接続 | Private IP のみ | Private IP のみ |
| 削除保護 | 無効 | 有効 |

<br>

### 4-2. バックアップ

> **GCPコンソール確認先:** **SQL** → `{prefix}-db` → **バックアップ** タブ

| 項目 | dev | prod |
|---|---|---|
| 自動バックアップ | 有効 | 有効 |
| バックアップ時間 | 03:00 JST | 03:00 JST |
| 保持期間 | 7日間 | 30日間 |
| PITR | 有効 | 有効 |

**PITR（ポイントインタイムリカバリ）:**

- バイナリログを使って「任意の時点」にデータベースを復元できる
- 自動バックアップだけでは「バックアップ取得時点」にしか戻せない
- PITRなら「障害発生の1分前」のような細かい指定が可能

<br>

### 4-3. 高可用性（HA）構成（prodのみ）

```
asia-northeast1-a          asia-northeast1-b
┌──────────────┐          ┌──────────────┐
│  プライマリ    │  同期     │  スタンバイ    │
│  Cloud SQL   │────────▶│  Cloud SQL   │
│  読み書き可    │ レプリケ   │  自動昇格     │
└──────────────┘          └──────────────┘
```

| 項目 | 説明 |
|---|---|
| 同期方式 | 準同期レプリケーション |
| フェイルオーバー | 自動（約60秒） |
| 接続先 | 同一Private IP（アプリ側の変更不要） |
| コスト | インスタンス料金が約2倍 |

<br>

### 4-4. Secret Manager（DBパスワード管理）

> **GCPコンソール確認先:** **セキュリティ** → **Secret Manager** → `{prefix}-db-password`

| 項目 | 値 |
|---|---|
| シークレットID | `{prefix}-db-password` |
| レプリケーション | 自動 |

**Secret Managerを使う理由:**

- パスワードをコードや設定ファイルにハードコーディングしない
- バージョン管理・アクセス制御・監査ログが自動
- GCEのサービスアカウントに `roles/secretmanager.secretAccessor` を付与して安全にアクセス

<br>

---

<br>

## 5. GCE 構成（modules/application）

<br>

### 5-1. インスタンス仕様

> **GCPコンソール確認先:** **Compute Engine** → **VMインスタンス** → `{prefix}-web` を選択

| 項目 | dev | prod |
|---|---|---|
| 名前 | `myapp-dev-web` | `myapp-prod-web` |
| マシンタイプ | e2-small (2vCPU, 2GB) | e2-medium (2vCPU, 4GB) |
| ゾーン | asia-northeast1-a | asia-northeast1-a |
| ブートディスク | Debian 12, pd-balanced 20GB | Debian 12, pd-balanced 20GB |
| 外部IP | なし | なし |
| ネットワークタグ | `web` | `web` |

<br>

### 5-2. サービスアカウント

> **GCPコンソール確認先:** **IAMと管理** → **サービスアカウント** → `{prefix}-web-sa`

| 項目 | 値 |
|---|---|
| 名前 | `{prefix}-web-sa` |
| 付与ロール | `roles/cloudsql.client`（Cloud SQL接続用） |
| 付与ロール | `roles/secretmanager.secretAccessor`（Secret Managerからパスワード取得用） |
| 付与ロール | `roles/logging.logWriter`（ログ書き込み用） |
| 付与ロール | `roles/monitoring.metricWriter`（メトリクス書き込み用） |

**最小権限の原則:**

- デフォルトのCompute Engineサービスアカウントは権限が広すぎる
- 必要最小限のロールだけを付与したカスタムサービスアカウントを使用

<br>

### 5-3. ソフトウェア構成（Ansibleで自動インストール）

| ソフトウェア | バージョン | 用途 | Ansibleロール |
|---|---|---|---|
| Apache | 2.4.x | Webサーバー | `apache` |
| PHP | 8.2.x | アプリケーション | `common` |
| Cloud SQL Auth Proxy | v2.14.3 | Cloud SQLへの安全な接続 | `cloud-sql-proxy` |
| Ops Agent | 最新 | ログ収集 + メトリクス送信 | `ops-agent` |
| gcloud CLI | 最新 | Secret Managerアクセス用 | `common` |

> **注:** 起動スクリプト（startup.sh）は最小限（Python確認のみ）。ソフトウェアのインストール・設定はすべてAnsibleで管理する。

<br>

### 5-4. Cloud SQL Auth Proxy

```
GCE内:
  アプリ (PHP) → localhost:3306 → Cloud SQL Auth Proxy → Cloud SQL (Private IP)
```

| 項目 | 説明 |
|---|---|
| 接続方式 | TCP localhost:3306 |
| DB認証 | パスワード認証（パスワードはSecret Managerで管理） |
| 暗号化 | TLS自動（設定不要） |
| 起動方式 | systemdサービスとして常駐 |

**接続フロー:**

```
アプリ起動時:
  Secret Manager → パスワード取得 → Cloud SQL Auth Proxy (localhost:3306) → Cloud SQL
```

**Cloud SQL Auth Proxyを使う理由:**

- Private IP直接接続でも動くが、Auth Proxyを挟むことでTLS暗号化が自動適用
- 接続管理（コネクションプーリング等）も自動

<br>

---

<br>

## 6. ロードバランサー構成（modules/application内）

<br>

### 6-1. 構成要素

> **GCPコンソール確認先:**
> - LB全体: ネットワークサービス → **ロードバランシング** → `{prefix}-urlmap`
> - 外部IP: VPCネットワーク → **IPアドレス** → `{prefix}-lb-ip`
> - バックエンド: ネットワークサービス → **ロードバランシング** → **バックエンド** タブ
> - ヘルスチェック: Compute Engine → **ヘルスチェック** → `{prefix}-hc`
> - インスタンスグループ: Compute Engine → **インスタンスグループ** → `{prefix}-ig`

```
Global Anycast IP
  │
  ▼
Forwarding Rule (HTTP:80 or HTTPS:443)
  │
  ▼
Target HTTP(S) Proxy
  │  ├─ SSL証明書（ドメインあり時、Googleマネージド）
  │
  ▼
URL Map
  │  ├─ デフォルト: backend-service
  │
  ▼
Backend Service ←── Cloud Armor Policy 適用
  │  ├─ ヘルスチェック: HTTP /health → 200
  │
  ▼
Instance Group ({prefix}-web)
```

<br>

### 6-2. 各コンポーネント詳細

| コンポーネント | 名前 | 設定 |
|---|---|---|
| 外部IP | `{prefix}-lb-ip` | グローバル静的IP |
| ヘルスチェック | `{prefix}-hc` | HTTP, ポート80, パス `/health`, 間隔10秒 |
| インスタンスグループ | `{prefix}-ig` | 非マネージド, GCEを登録, lifecycle連動 |
| バックエンドサービス | `{prefix}-backend` | HTTP, Cloud Armor紐付け |
| URLマップ | `{prefix}-urlmap` | デフォルトバックエンド |

<br>

### 6-3. インスタンスグループの lifecycle 連動

**背景（実際に発生したインシデント）:**

GCEインスタンスが `terraform apply` によって再作成（delete → insert）されると、Unmanaged Instance Group（非マネージドIG）からメンバーが失われ、LBが503を返す障害が発生する。これはGCPの仕様で、GCE停止・削除時にIGメンバーシップが自動解除されるため。

**再作成が発生する条件:**

GCEの変更がすべて再作成になるわけではない。変更する属性によってin-place更新か再作成（ForceNew）かが決まる。

| 動作 | 属性の例 |
|---|---|
| **in-place更新**（再作成されない） | `labels`, `metadata`（startup-script内容）, `tags`, `machine_type`（※停止→変更→起動） |
| **再作成**（delete → insert） | `boot_disk`（イメージ・サイズ変更）, `network_interface`のサブネット, `zone`, `name`, `service_account` |

`terraform plan` の出力で `# forces replacement` と表示されるため、**apply前に必ず確認し、再作成が本当に必要か判断すること。**

```
# forces replacement が表示される例
# google_compute_instance.web must be replaced
-/+ resource "google_compute_instance" "web" {
      ~ boot_disk {  # forces replacement
```

**1台構成でのダウンタイム:**

現在の構成ではGCEが1台のため、再作成が発生すると**一時的にサービスが停止する**（数分〜10分程度）。

```
旧GCE削除 → LBが503を返し始める
  → 新GCE作成（1〜2分）
  → startup-script実行（Apache/PHP/Proxy等のインストール・起動）
  → IG再作成 → 新GCEをメンバー登録
  → ヘルスチェック通過（interval 10秒 × 数回）
  → LBがトラフィックを流し始める
```

| 回避策 | 内容 | コスト |
|---|---|---|
| **再作成を避ける** | `terraform plan` で `forces replacement` が出たら慎重に判断 | なし |
| **メンテナンスウィンドウ** | 深夜等のアクセスが少ない時間に実施 | なし |
| **GCE複数台構成 / MIG化** | ローリングアップデートで無停止更新が可能 | GCEコスト増・構成の複雑化 |

**対策:**

Terraformコードで `replace_triggered_by` を設定し、GCE再作成時にIGも連動して再作成されるようにしている。

```hcl
resource "google_compute_instance_group" "web" {
  name = "${var.prefix}-ig"
  zone = var.zone

  instances = [google_compute_instance.web.self_link]

  named_port {
    name = "http"
    port = 80
  }

  lifecycle {
    replace_triggered_by = [google_compute_instance.web.id]
  }
}
```

| 項目 | 説明 |
|---|---|
| `instances` | `.id` ではなく `.self_link` を使用（GCP APIとの整合性） |
| `replace_triggered_by` | GCEの `id` が変わったらIGも再作成 |
| 効果 | GCE再作成 → IG再作成 → バックエンド登録が自動回復 |

> **注意:** GCEをGCPコンソールや `gcloud` から手動で停止・再起動した場合も、IGからメンバーが外れる。その場合は `terraform apply` を実行するか、`gcloud compute instance-groups unmanaged add-instances` で手動再登録が必要。

<br>

### 6-4. ドメイン有無による動作切り替え

| ドメイン設定 | 動作 |
|---|---|
| 空（デフォルト） | HTTP (ポート80) で直接バックエンドへ |
| ドメインあり | HTTPS (443) + Googleマネージド証明書 + HTTP→HTTPSリダイレクト |

Terraformの `count` で動的に切り替え（不要なリソースは作成しない）。

<br>

### 6-5. HTTPS設定（Google Managed SSL証明書）

> **GCPコンソール確認先:** ネットワークサービス → **ロードバランシング** → 左メニュー **証明書** → `{prefix}-cert`
> （ステータスが ACTIVE なら発行完了）

| 項目 | 値 |
|---|---|
| 証明書名 | `{prefix}-cert` |
| タイプ | Google Managed（自動発行・自動更新） |
| 料金 | **無料**（LB利用時） |
| 対象ドメイン | `terraform.tfvars` の `domain` 変数で指定 |
| プロビジョニング時間 | 15〜30分（最大数時間） |

**有効化手順:**

```hcl
# terraform.tfvars に追加するだけ
domain = "example.com"
```

```bash
terraform plan -var="db_password=xxx"   # 7 to add 確認
terraform apply -var="db_password=xxx"  # 適用
```

**作成されるリソース:**

| リソース | 説明 |
|---|---|
| `google_compute_managed_ssl_certificate` | SSL証明書（自動発行） |
| `google_compute_target_https_proxy` | HTTPS Proxy |
| `google_compute_global_forwarding_rule` (443) | HTTPS転送ルール |
| `google_compute_url_map` (redirect) | HTTP→HTTPSリダイレクト |

**HTTP→HTTPSリダイレクト:**

```
ユーザー → http://example.com/ → 301リダイレクト → https://example.com/
```

<br>

### 6-6. ドメイン・DNS設定

<br>

#### ドメイン取得

| 項目 | 値 |
|---|---|
| ドメイン | `example.com` |
| レジストラ | Cloudflare |
| 年額 | $12.30 |

<br>

#### DNS設定（Cloudflare）

| タイプ | 名前 | 値 | プロキシ状態 |
|---|---|---|---|
| A | `@` | `x.x.x.x`（LBのIP） | **DNS only（グレーの雲）** |

**重要: Cloudflare利用時の注意点**

- プロキシ状態を **DNS only（グレーの雲）** にすること
- **Proxied（オレンジの雲）にするとGoogle Managed SSL証明書のプロビジョニングが失敗する**
- Cloudflareがプロキシすると、GoogleがドメインのIPを確認できずSSL発行できないため

<br>

#### DNS伝播に関する注意

- 新規ドメインの場合、NSレコードの伝播に最大数時間〜48時間かかることがある
- Aレコード設定前にDNSクエリが飛ぶと、NXDOMAINのネガティブキャッシュ（TTL最大1時間）が残る
- 確認コマンド:

```bash
# CloudflareのNSに直接確認（即時反映）
dig example.com A @aspen.ns.cloudflare.com +short

# パブリックDNSでの伝播確認
dig example.com A @8.8.8.8 +short

# SSL証明書の状態確認
gcloud compute ssl-certificates describe myapp-dev-cert \
  --global --format="value(managed.status,managed.domainStatus)"
# → ACTIVE になればHTTPSアクセス可能
```

<br>

---

<br>

## 7. Cloud Armor 構成（modules/security）

<br>

### 7-1. セキュリティポリシー

> **GCPコンソール確認先:** ネットワークセキュリティ → **Cloud Armor ポリシー** → `{prefix}-armor-policy`

| 項目 | 値 |
|---|---|
| ポリシー名 | `{prefix}-armor-policy` |
| 適用先 | バックエンドサービス |

<br>

### 7-2. ルール一覧

| 優先度 | 条件 | アクション | dev | prod |
|---|---|---|---|---|
| 1000 | SQLインジェクション | deny(403) | 同じ | 同じ |
| 1001 | XSS | deny(403) | 同じ | 同じ |
| 1002 | レート制限 | throttle→deny(429) | 100 req/min | 200 req/min |
| 2147483647 | デフォルト | allow | 同じ | 同じ |

<br>

---

<br>

## 8. デモアプリケーション

<br>

### 8-1. ページ一覧

| URL | ページ名 | 内容 |
|---|---|---|
| `/` | トップページ | サーバー情報（Hostname, IP, PHP Version, OS）+ DB接続ステータス表示 |
| `/db-check.php` | DB Check | Cloud SQL Auth Proxyの稼働状態、DB一覧、テーブル一覧 |
| `/db-sample.php` | メモ帳アプリ | CRUD操作（追加・削除）でDB読み書き確認 |
| `/health` | ヘルスチェック | LBヘルスチェック用（`OK` を返す静的ファイル） |

<br>

### 8-2. アプリケーション管理方式

デモアプリのPHPファイルは **Ansible の `webapp` ロール**で管理する。

```
ansible/roles/webapp/files/
├── db-config.php      ← DB接続設定（共通）
├── index.php          ← トップページ
├── db-check.php       ← DB接続チェック
├── db-sample.php      ← メモ帳CRUDアプリ
└── health             ← ヘルスチェック用静的ファイル
```

PHPファイルは独立したファイルとして管理されるため、IDE での編集・差分管理・コードレビューが容易。

**デプロイ方法:**

```bash
# ローカル（WSL2）から IAP SSH経由で実行
cd terraform/ansible
ansible-playbook -i inventory/dev.yml playbook.yml --tags webapp
```

> **注:** PHPファイルの変更は Ansible で差分適用するだけで済み、GCE再作成は不要。

<br>

### 8-3. DB接続の仕組み

```
Ansible実行時 (db-configロール):
  ① gcloud secrets → Secret Managerから DBパスワード取得
  ② /etc/myapp-db.conf に接続情報を書き出し（root:www-data, 640）

アプリ実行時:
  ③ PHPアプリ → db-config.php → /etc/myapp-db.conf 読み込み
  ④ mysqli_connect → localhost:3306 → Cloud SQL Auth Proxy → Cloud SQL
```

<br>

### 8-4. DB設定ファイル

| 項目 | 値 |
|---|---|
| パス | `/etc/myapp-db.conf` |
| パーミッション | 640（root:www-data） |
| 内容 | DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD |
| 管理方法 | Ansible `db-config` ロール（テンプレート: `myapp-db.conf.j2`） |

- パスワードはSecret Managerから Ansible実行時に取得（ハードコーディングしない）
- www-data（Apache実行ユーザー）のみ読み取り可能

<br>

### 8-5. セキュリティ対策

| 対策 | 実装 |
|---|---|
| SQLインジェクション防御 | プリペアドステートメント使用（`mysqli_prepare` + `bind_param`） |
| XSS防御 | `htmlspecialchars()` で出力エスケープ |
| パスワード管理 | Secret Manager + 設定ファイル（コードに含めない） |
| CSRF | 簡易的な `confirm()` ダイアログ（デモ用） |

<br>

---

<br>

## 9. Ansible 構成管理

<br>

### 9-1. 概要

GCE内のソフトウェアインストール・設定・アプリデプロイはすべて **Ansible** で管理する。

```
ローカルPC (WSL2)                              GCE
┌───────────────────────┐                    ┌──────────────────┐
│  Ansible               │  IAP SSH経由       │  Python のみ      │
│  ansible-playbook      │──────────────────▶│  (Debian 12標準)   │
│                        │                    │  Ansibleインストール │
│  必要: Ansible, gcloud │                    │  不要              │
└───────────────────────┘                    └──────────────────┘
```

- Ansible はローカル（制御ノード）からIAP SSH経由でGCE（管理対象）にリモート実行
- GCE側にAnsibleのインストールは不要（Pythonのみで動作、Debian 12に標準搭載）
- startup.sh は最小限（Python確認のみ）に縮小済み

<br>

### 9-2. ディレクトリ構成

```
terraform/ansible/
├── ansible.cfg                    ← IAP SSH接続設定
├── playbook.yml                   ← メインPlaybook
├── inventory/
│   ├── dev.yml                    ← dev環境ホスト定義
│   └── prod.yml                   ← prod環境ホスト定義
├── group_vars/
│   ├── all.yml                    ← 全環境共通変数
│   ├── dev.yml                    ← dev環境変数
│   └── prod.yml                   ← prod環境変数
└── roles/
    ├── common/                    ← apt, gcloud CLI
    ├── cloud-sql-proxy/           ← Proxy DL + systemdサービス
    ├── db-config/                 ← Secret Manager → DB設定ファイル
    ├── apache/                    ← PHP ini, server-status, Apache有効化
    ├── webapp/                    ← PHPアプリファイル配置
    └── ops-agent/                 ← Ops Agentインストール + 設定
```

<br>

### 9-3. ロール一覧

| ロール | 役割 | 主な設定ファイル |
|---|---|---|
| `common` | パッケージインストール（Apache, PHP, gcloud CLI） | — |
| `cloud-sql-proxy` | Cloud SQL Auth Proxy のDL・systemdサービス登録 | `cloud-sql-proxy.service.j2` |
| `db-config` | Secret ManagerからDBパスワード取得、設定ファイル生成 | `myapp-db.conf.j2` |
| `apache` | PHPログ設定、server-status有効化、Apache起動 | `99-logging.ini.j2`, `status.conf.j2` |
| `webapp` | デモPHPアプリ・ヘルスチェックファイルのデプロイ | `db-config.php`, `index.php` 等 |
| `ops-agent` | Ops Agentインストール、ログ・メトリクス収集設定 | `config.yaml.j2` |

<br>

### 9-4. 実行方法

```bash
# 全ロール実行（初回セットアップ）
cd terraform/ansible
ansible-playbook -i inventory/dev.yml playbook.yml

# 特定ロールのみ実行（PHPファイル更新時）
ansible-playbook -i inventory/dev.yml playbook.yml --tags webapp

# prod環境への適用
ansible-playbook -i inventory/prod.yml playbook.yml
```

<br>

### 9-5. Terraform との役割分担

```
terraform apply                    ansible-playbook
  │                                  │
  ├─ VPC / サブネット                 ├─ Apache / PHP インストール
  ├─ ファイアウォール                  ├─ Cloud SQL Auth Proxy 設定
  ├─ Cloud SQL                      ├─ DB設定ファイル生成
  ├─ GCE（箱だけ作る）                ├─ PHPアプリデプロイ
  ├─ LB / Cloud Armor               ├─ Ops Agent 設定
  └─ Secret Manager                 └─ Apache / サービス起動
```

| 観点 | Terraform | Ansible |
|---|---|---|
| 対象 | GCPインフラリソース | GCE内のソフトウェア・設定 |
| 変更時 | `terraform apply`（インフラ変更） | `ansible-playbook`（設定変更） |
| GCE再作成 | 属性によっては発生する | **発生しない** |
| 冪等性 | あり | あり |

> **メリット:** PHPや設定の変更ではGCE再作成が不要になり、Ansibleで差分適用するだけで済む。セクション6-3で議論したダウンタイムリスクが大幅に軽減される。

<br>

### 9-6. IAP SSH 接続設定

`ansible.cfg` で IAP トンネル経由のSSH接続を設定:

```ini
[ssh_connection]
ssh_args = -o ProxyCommand="gcloud compute start-iap-tunnel %h 22
  --listen-on-stdin --zone=asia-northeast1-a --quiet"
pipelining = True
```

- GCEに外部IPは不要（IAP経由で接続）
- `pipelining = True` で実行速度を向上

### 9-7. Ansible SSH設定（.env）

`setup.sh` は実行時に以下を自動処理するため、`ansible.cfg` の直接編集は不要:

- **inventory動的生成**: `.env` の `PROJECT_NAME` + 環境名からホスト名を生成（例: `rubese-dev-web`）
- **SSH設定**: 環境変数（`ANSIBLE_*`）で注入し、world writable directory の問題を回避

`.env` で設定可能なSSH関連の変数:

| 変数 | デフォルト値 | 説明 |
|---|---|---|
| `GCE_SSH_USER` | 現在のOSユーザー（`whoami`） | GCEへのSSHユーザー名 |
| `GCE_SSH_KEY` | `~/.ssh/google_compute_engine` | SSH秘密鍵パス（`gcloud compute ssh` が自動生成） |

> **注意:** 初回は `gcloud compute ssh <インスタンス名> --zone=<ゾーン> --tunnel-through-iap` を実行して、SSH鍵の生成とOS Login設定を完了させてください。

### 9-8. WSL2環境での注意事項

WSL2（Windows Subsystem for Linux）から実行する場合、以下の問題に注意が必要:

#### CRLF改行問題

Windowsマウント（`/mnt/d/` 等）上のファイルはCRLF改行になることがある。シェルスクリプトがCRLFだと `cannot execute: required file not found` エラーになる。

```bash
# 確認
file scripts/setup.sh
# → "with CRLF line terminators" と表示されたらNG

# 修正
tr -d '\r' < scripts/setup.sh > /tmp/setup.sh && cp /tmp/setup.sh scripts/setup.sh
```

> **注意:** WSL2のWindowsマウント上では `sed -i` が効かない場合がある。`tr` + `cp` で対処する。

#### ansible.cfg が無視される（world writable directory）

Windowsマウント上のディレクトリは `777` パーミッション（world writable）となるため、Ansibleがセキュリティ上 `ansible.cfg` を無視する。

```
[WARNING]: Ansible is being run in a world writable directory, ignoring it as an ansible.cfg source.
```

**対策:** `setup.sh` では `ansible.cfg` を使わず、環境変数（`ANSIBLE_REMOTE_USER`, `ANSIBLE_SSH_ARGS` 等）で設定を注入している。

<br>

---

<br>

## 10. Cloud Logging / Monitoring（監視・ログ）

<br>

### 10-1. Ops Agent 概要

```
GCE内:
  Apache access.log  ──┐
  Apache error.log   ──┤
  PHP php_errors.log ──┼→ Ops Agent ──→ Cloud Logging（ログ検索・アラート）
  syslog / auth.log  ──┤                     +
  CPU / メモリ / ディスク ┘              Cloud Monitoring（メトリクスグラフ）
```

- **Ops Agent** = Cloud Logging + Cloud Monitoring を1つのエージェントで担当
- GCE起動スクリプト（startup.sh）で自動インストール・設定

<br>

### 10-2. ログ収集設定

| ログ種別 | 収集元 | ラベル | 設定 |
|---|---|---|---|
| Apache アクセスログ | `/var/log/apache2/access.log` | — | 構造化パース（IP, URL, ステータスコード） |
| Apache エラーログ | `/var/log/apache2/error.log` | — | エラーレベル付き |
| PHP エラーログ | `/var/log/apache2/php_errors.log` | `app=php` | 専用ファイルに分離出力 |
| Cloud SQL Proxy ログ | `/var/log/syslog`（フィルタ） | `app=cloud-sql-proxy` | キーワードフィルタ |
| システムログ | `/var/log/syslog`, `/var/log/auth.log` | — | SSH接続記録等 |
| Cloud SQL ログ | 自動収集 | — | マネージドサービスのため設定不要 |

<br>

### 10-3. メトリクス収集

| メトリクス種別 | 収集方法 | 内容 |
|---|---|---|
| ホストメトリクス | Ops Agent 自動収集 | CPU使用率, メモリ使用量, ディスクI/O |
| Apache メトリクス | `server-status` モジュール経由 | リクエスト数, アクティブ接続, レスポンス時間 |
| Cloud SQL メトリクス | 自動（マネージドサービス） | CPU, メモリ, 接続数, クエリ数 |

<br>

### 10-4. Apache server-status

| 項目 | 値 |
|---|---|
| URL | `http://127.0.0.1/server-status?auto` |
| アクセス制限 | `Require local`（ローカルのみ、外部からアクセス不可） |
| 用途 | Ops Agent がメトリクスを収集するためのエンドポイント |

<br>

### 10-5. PHP ログ設定

| 項目 | 値 |
|---|---|
| 設定ファイル | `/etc/php/8.2/apache2/conf.d/99-logging.ini` |
| log_errors | On |
| error_log | `/var/log/apache2/php_errors.log` |
| error_reporting | `E_ALL & ~E_DEPRECATED & ~E_STRICT` |

- PHPエラーをApacheエラーログと分離して専用ファイルに出力
- Ops Agent でラベル `app=php` を付与して Cloud Logging で絞り込み可能

<br>

### 10-6. GCPコンソールでの確認方法

<br>

#### ■ ログ確認（Cloud Logging）

**メニュー:** Cloud Console → **Logging** → **Logs Explorer**

| 確認したいログ | フィルタ設定 |
|---|---|
| Apache アクセスログ | リソースタイプ: `GCE Instance` → ログ名: `apache_access` |
| Apache エラーログ | リソースタイプ: `GCE Instance` → ログ名: `apache_error` |
| PHP エラーログ | `labels.app="php"` でフィルタ |
| Cloud SQL Proxy ログ | `labels.app="cloud-sql-proxy"` でフィルタ |
| システムログ（syslog） | リソースタイプ: `GCE Instance` → ログ名: `syslog` |
| SSH接続記録 | リソースタイプ: `GCE Instance` → ログ名: `authlog` |
| Cloud SQL ログ | リソースタイプ: `Cloud SQL Database` |
| LBアクセスログ | リソースタイプ: `HTTP Load Balancer` → ログ名: `requests` |

**Logs Explorer の使い方:**

1. 上部の「リソース」ドロップダウンで対象リソースを選択
2. 「ログ名」で種別を絞り込み
3. 時間範囲を設定（右上のタイムピッカー）
4. クエリ欄に直接フィルタを入力することも可能

```
# クエリ例: PHPエラーのみ表示
resource.type="gce_instance"
labels.app="php"

# クエリ例: 500エラーのHTTPリクエスト
resource.type="http_load_balancer"
httpRequest.status=500

# クエリ例: 特定時間帯のApacheアクセスログ
resource.type="gce_instance"
log_name="projects/your-gcp-project-id/logs/apache_access"
```

<br>

#### ■ GCEリソース使用率（Compute Engine）

**メニュー:** Cloud Console → **Compute Engine** → **VMインスタンス** → `{prefix}-web` → **モニタリング** タブ

| グラフ | 確認できる内容 |
|---|---|
| CPU使用率 | vCPUの使用率（%）、スパイクの検知 |
| ネットワークバイト数 | 送受信トラフィック量（bytes/sec） |
| ディスク読み書き | ディスクI/Oオペレーション数（IOPS） |
| ディスクスループット | ディスク読み書き速度（bytes/sec） |

**メニュー:** Cloud Console → **Compute Engine** → **VMインスタンス** → `{prefix}-web` → **詳細** タブ

| 項目 | 確認できる内容 |
|---|---|
| マシンタイプ | e2-small等のスペック |
| ネットワークインターフェース | 内部IP、サブネット、ネットワークタグ |
| ディスク | ブートディスクの種類・サイズ |
| サービスアカウント | 紐付けられたSA |
| 起動スクリプト | metadata_startup_script の内容 |

<br>

#### ■ Cloud SQL リソース使用率

**メニュー:** Cloud Console → **SQL** → `{prefix}-db` → **モニタリング** タブ（概要）

| グラフ | 確認できる内容 |
|---|---|
| CPU使用率 | DBインスタンスのCPU負荷 |
| メモリ使用量 | DBインスタンスのメモリ使用量 |
| ストレージ使用量 | ディスク使用量と自動拡張の状況 |
| アクティブ接続数 | 現在のDB接続数 |
| クエリ数 | SELECT/INSERT/UPDATE/DELETE の秒間実行数 |
| レプリケーション遅延 | HA構成時のプライマリ⇔スタンバイの遅延 |
| ネットワーク送受信 | DBのネットワークトラフィック |

**メニュー:** Cloud Console → **SQL** → `{prefix}-db` → **オペレーション** タブ

| 項目 | 確認できる内容 |
|---|---|
| オペレーション一覧 | 作成・バックアップ・再起動等の操作履歴 |

**メニュー:** Cloud Console → **SQL** → `{prefix}-db` → **接続** タブ

| 項目 | 確認できる内容 |
|---|---|
| Private IP | Cloud SQLのプライベートIPアドレス |
| 接続名 | Cloud SQL Auth Proxyで使う接続名 |

<br>

#### ■ ロードバランサー監視

**メニュー:** Cloud Console → **ネットワークサービス** → **ロードバランシング** → `{prefix}-urlmap` → **モニタリング** タブ

| グラフ | 確認できる内容 |
|---|---|
| リクエスト数 | 秒間リクエスト数（RPS） |
| エラー率 | 4xx/5xx のレスポンス割合 |
| レイテンシ | バックエンドの応答時間分布 |
| トラフィック | 送受信バイト数 |

**メニュー:** Cloud Console → **ネットワークサービス** → **ロードバランシング** → `{prefix}-urlmap` → **バックエンド** タブ

| 項目 | 確認できる内容 |
|---|---|
| ヘルスチェック状態 | 正常（緑）/ 異常（赤）のインスタンス |
| バックエンドの応答性 | ヘルスチェック成功率 |

<br>

#### ■ Cloud Monitoring ダッシュボード・アラート

**メニュー:** Cloud Console → **Monitoring** → **ダッシュボード**

| ダッシュボード | 確認できる内容 |
|---|---|
| GCE Instances | 全VMのCPU・メモリ・ディスク・ネットワーク一覧 |
| Cloud SQL | 全DBインスタンスのメトリクス一覧 |
| カスタムダッシュボード | 自分で作成したグラフの組み合わせ |

**メニュー:** Cloud Console → **Monitoring** → **Metrics Explorer**

- 任意のメトリクスを自由に検索・グラフ化できる
- 例: `compute.googleapis.com/instance/cpu/utilization` でCPU使用率

**メニュー:** Cloud Console → **Monitoring** → **アラート**

| 設定 | 説明 |
|---|---|
| アラートポリシー作成 | 条件（CPU > 80% が5分継続等）を定義 |
| 通知チャンネル | メール、Slack、PagerDuty等に通知 |
| インシデント | 発生中のアラート一覧 |

<br>

#### ■ Cloud Armor ログ

**メニュー:** Cloud Console → **ネットワークセキュリティ** → **Cloud Armor ポリシー** → `{prefix}-armor-policy` → **ログ** タブ

| 確認できる内容 | 説明 |
|---|---|
| ブロックされたリクエスト | SQLi/XSS/レート制限でdenyされたリクエスト |
| ルール別ヒット数 | どのルールがどれだけ発動したか |
| リクエスト元IP | ブロックされた送信元IPアドレス |

**Logs Explorerでの確認:**

```
# Cloud Armorでブロックされたリクエスト
resource.type="http_load_balancer"
jsonPayload.enforcedSecurityPolicy.outcome="DENY"
```

<br>

#### ■ IAP 監査ログ

**メニュー:** Cloud Console → **Logging** → **Logs Explorer**

```
# IAP経由のSSH接続ログ
resource.type="gce_instance"
protoPayload.methodName="google.cloud.iap.v1.IdentityAwareProxyService"
```

| 確認できる内容 | 説明 |
|---|---|
| 接続元ユーザー | どのGoogleアカウントがSSHしたか |
| 接続日時 | いつ接続したか |
| 対象インスタンス | どのVMに接続したか |

<br>

### 10-7. 有効化するGCP API

> **GCPコンソール確認先:** **APIとサービス** → **有効なAPIとサービス** → API名で検索

| API | 用途 |
|---|---|
| `logging.googleapis.com` | Cloud Logging |
| `monitoring.googleapis.com` | Cloud Monitoring |
| `compute.googleapis.com` | Compute Engine |
| `sqladmin.googleapis.com` | Cloud SQL Admin |
| `servicenetworking.googleapis.com` | Service Networking |
| `secretmanager.googleapis.com` | Secret Manager |
| `iap.googleapis.com` | Identity-Aware Proxy |

Terraform（environments/dev,prod の main.tf）で自動有効化。

<br>

---

<br>

## 11. SSH接続（IAP）

<br>

### 11-1. IAP (Identity-Aware Proxy) とは

> **GCPコンソール確認先:** **セキュリティ** → **Identity-Aware Proxy** → **SSHおよびTCPリソース** タブ

- Googleの認証基盤を通してSSH接続を行う仕組み
- GCEに外部IPやSSHポートの公開が不要
- 接続元IPではなく「Googleアカウント + IAM権限」で認可
- 全セッションがログに記録される（監査対応）

<br>

### 11-2. 接続方法

```bash
# dev環境へIAP経由SSH
gcloud compute ssh myapp-dev-web \
  --zone=asia-northeast1-a \
  --tunnel-through-iap

# prod環境へIAP経由SSH
gcloud compute ssh myapp-prod-web \
  --zone=asia-northeast1-a \
  --tunnel-through-iap

# ポートフォワーディング（ローカルからDB接続等）
gcloud compute ssh myapp-dev-web \
  --zone=asia-northeast1-a \
  --tunnel-through-iap \
  -- -L 3306:localhost:3306
```

<br>

---

<br>

## 12. 命名規則

<br>

| リソース種別 | 命名パターン | dev例 | prod例 |
|---|---|---|---|
| VPC | `{prefix}-vpc` | `myapp-dev-vpc` | `myapp-prod-vpc` |
| サブネット | `{prefix}-subnet` | `myapp-dev-subnet` | `myapp-prod-subnet` |
| ファイアウォール | `{prefix}-{action}-{target}` | `myapp-dev-allow-iap-ssh` | `myapp-prod-allow-iap-ssh` |
| GCE | `{prefix}-web` | `myapp-dev-web` | `myapp-prod-web` |
| Cloud SQL | `{prefix}-db` | `myapp-dev-db` | `myapp-prod-db` |
| サービスアカウント | `{prefix}-web-sa` | `myapp-dev-web-sa` | `myapp-prod-web-sa` |
| LB関連 | `{prefix}-{component}` | `myapp-dev-lb-ip` | `myapp-prod-lb-ip` |
| Cloud Armor | `{prefix}-armor-policy` | `myapp-dev-armor-policy` | `myapp-prod-armor-policy` |
| Secret Manager | `{prefix}-db-password` | `myapp-dev-db-password` | `myapp-prod-db-password` |

**prefix = `{project_name}-{env}`** で全リソースが環境ごとに一意になる。

<br>

---

<br>

## 13. テスト終了後の削除

```bash
# dev環境の全リソース削除
cd environments/dev
terraform destroy

# prod環境の全リソース削除（削除保護を先に無効化する必要あり）
cd environments/prod
# Cloud SQLの deletion_protection を false に変更してから
terraform destroy
```

コスト発生を防ぐため、テスト終了後は全リソースを削除する。

<br>

---

<br>

## 14. ローカル環境セットアップ手順

<br>

### 14-1. 前提環境

| 項目 | 値 |
|---|---|
| OS | WSL2 (Ubuntu) |
| シェル | bash |
| Googleアカウント | GCPプロジェクトのオーナー権限を持つアカウント |

<br>

### 14-2. gcloud CLI インストール

```bash
# 方法1: aptリポジトリ経由（推奨）
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

# GPGキー追加
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

# リポジトリ追加
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
  https://packages.cloud.google.com/apt cloud-sdk main" | \
  sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

# インストール
sudo apt-get update && sudo apt-get install -y google-cloud-cli
```

```bash
# 方法2: インストールスクリプト
curl https://sdk.cloud.google.com | bash
# シェル再起動後に使用可能
```

<br>

### 14-3. gcloud 初期設定・認証

gcloud CLIには**2種類の認証**がある。どちらも必要。

```
┌─────────────────────────────────────────────────────┐
│  gcloud auth login                                  │
│  → gcloud コマンド自体の認証                          │
│  → gcloud compute ssh, gcloud projects list 等      │
├─────────────────────────────────────────────────────┤
│  gcloud auth application-default login              │
│  → アプリケーション（Terraform等）の認証               │
│  → Terraform が GCP API を呼ぶ際に使用               │
└─────────────────────────────────────────────────────┘
```

<br>

#### Step 1: gcloud 初期化

```bash
gcloud init
```

- ブラウザが開く → Googleアカウントでログイン
- WSL2でブラウザが開かない場合、表示されるURLをWindowsのブラウザにコピペ
- プロジェクト選択 → `your-gcp-project-id` (myapp)
- リージョン設定 → `asia-northeast1-a`

<br>

#### Step 2: gcloud CLI 認証

```bash
gcloud auth login
```

- gcloud コマンド（`gcloud compute ssh` 等）を使うための認証
- ブラウザでGoogleアカウントログイン → 「許可」

<br>

#### Step 3: 認証確認

```bash
# 認証済みアカウント確認
gcloud auth list

# 現在のプロジェクト・リージョン確認
gcloud config list

# プロジェクト一覧（API疎通確認）
gcloud projects list
```

<br>

### 14-4. Terraform インストール

```bash
# HashiCorp GPGキー追加
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

# リポジトリ追加
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

# インストール
sudo apt-get update && sudo apt-get install -y terraform

# バージョン確認
terraform --version
```

<br>

### 14-5. Ansible インストール

```bash
# pipx 経由でインストール（推奨）
sudo apt-get install -y pipx
pipx install ansible-core

# バージョン確認
ansible --version
```

- Ansible はローカル（WSL2）にのみインストールすればよい
- GCE側へのインストールは不要（Python標準搭載で動作）

<br>

### 14-6. Terraform 用 OAuth 認証（ADC）

Terraform が GCP API を呼ぶために**アプリケーションデフォルト認証（ADC）**が必要。
`gcloud auth login` とは別の認証。

```bash
gcloud auth application-default login
```

- ブラウザが開く → Googleアカウントでログイン → 「許可」
- `Credentials saved to file: ~/.config/gcloud/application_default_credentials.json` と表示されれば成功
- この認証情報は Terraform が自動的に読み取る（Terraformのコードに認証情報を書く必要はない）

<br>

### 14-7. 認証の関係まとめ

```
ローカルPC (WSL2)
  │
  ├── gcloud auth login
  │     → ~/.config/gcloud/credentials.db に保存
  │     → gcloud コマンドが使える
  │     → 用途: gcloud compute ssh, gcloud projects list 等
  │
  └── gcloud auth application-default login
        → ~/.config/gcloud/application_default_credentials.json に保存
        → Terraform / SDKが使える
        → 用途: terraform plan, terraform apply 等
```

| 認証 | 保存先 | 用途 | 有効期限 |
|---|---|---|---|
| `gcloud auth login` | `~/.config/gcloud/credentials.db` | gcloud CLI | 無期限（revoke するまで） |
| `gcloud auth application-default login` | `~/.config/gcloud/application_default_credentials.json` | Terraform, SDK | 無期限（revoke するまで） |

<br>

### 14-8. トラブルシューティング

| エラー | 原因 | 対処 |
|---|---|---|
| `command not found: gcloud` | gcloud未インストール or PATH未設定 | 14-2の手順でインストール、またはシェル再起動 |
| `command not found: terraform` | Terraform未インストール | 14-4の手順でインストール |
| `command not found: ansible` | Ansible未インストール | 14-5の手順でインストール |
| `No credentials loaded` | ADC未設定 | `gcloud auth application-default login` を実行 |
| `Permission denied` | アカウントに権限がない | GCPコンソールでIAMロール確認（Owner or Editor） |
| `API not enabled` | GCP APIが未有効化 | Terraformコードで自動有効化される（または手動で `gcloud services enable <API>`） |
| Ansible SSH接続エラー | IAP権限不足 or GCE未起動 | `gcloud compute ssh` で直接接続確認、IAM権限確認 |
| ブラウザが開かない（WSL2） | WSLからブラウザを起動できない | 表示されるURLをWindowsブラウザにコピペ |
| `cannot execute: required file not found` | シェルスクリプトがCRLF改行（WSL2） | `tr -d '\r' < scripts/setup.sh > /tmp/fix && cp /tmp/fix scripts/setup.sh` |
| `ansible.cfg` が無視される（WARNING） | Windowsマウント上はworld writable | `setup.sh` が環境変数で自動回避するため対処不要 |
| Ansible `Permission denied (publickey)` | SSHユーザー名/鍵が不一致 | `.env` の `GCE_SSH_USER` / `GCE_SSH_KEY` を確認（9-7参照） |
| terraform.tfvarsのプレースホルダが使われる | tfvarsに共通値が残っている | 共通値はtfvarsから削除し `.env` → `TF_VAR_` のみで管理 |
| Ansible `--tags` でタスクが実行されない | playbook.yml のロールにタグ未定義 | `{ role: webapp, tags: ['webapp'] }` 形式でタグを付与 |
| Ops Agent 起動失敗 (`filter_pattern`) | `files` レシーバーに `filter_pattern` は無効 | `filter_pattern` を削除し、syslogパイプラインに統合 |
| Ansible テンプレート `not found` エラー | タスクの `src:` とテンプレートファイル名が不一致 | ファイル名を汎用化（例: `db.conf.j2`）し `src:` を合わせる |
| LB IP で `ERR_CONNECTION_CLOSED` | HTTPSリダイレクト有効 + SSL証明書未発行 | DNS Aレコード設定前はHTTPリダイレクトを無効化するか、`domain` を空にする |
| DB接続で `Access denied` | `main.tf` にDB名/ユーザー名がハードコード（`myapp`）されていた | `.env` → `TF_VAR_db_name` / `TF_VAR_db_user` で注入するよう修正 |
| `terraform apply` で `database exists` エラー | `gcloud` で手動作成したDBとTerraform管理が競合 | `terraform import` で既存リソースをstateに取り込む |
| forwarding rule の `IP address in-use` エラー | 同一IPで新旧ルールの作成・削除が競合 | 再度 `terraform apply` を実行すれば解消 |

<br>

### 14-9. GCPコンソール確認先 一覧

| リソース | GCPコンソールメニュー | 確認できる内容 |
|---|---|---|
| VPC | VPCネットワーク → **VPCネットワーク** | ネットワーク一覧、サブネット、ピアリング |
| サブネット | VPCネットワーク → **VPCネットワーク** → VPC選択 → **サブネット** | CIDR、Private Google Access、フローログ |
| ファイアウォール | VPCネットワーク → **ファイアウォール** | ルール一覧、優先度、ソース/ターゲット |
| Cloud Router | ネットワーク接続 → **Cloud Routers** | ルーター設定、NAT紐付け |
| Cloud NAT | ネットワークサービス → **Cloud NAT** | NAT設定、IPアドレス割り当て |
| Private Services Access | VPCネットワーク → VPC選択 → **プライベートサービス接続** | IP範囲、ピアリング状態 |
| Cloud SQL | **SQL** | インスタンス一覧、接続情報、Private IP |
| Cloud SQL バックアップ | **SQL** → インスタンス選択 → **バックアップ** | バックアップ一覧、PITR設定 |
| Cloud SQL ユーザー | **SQL** → インスタンス選択 → **ユーザー** | DBユーザー一覧 |
| Cloud SQL データベース | **SQL** → インスタンス選択 → **データベース** | DB一覧 |
| Secret Manager | セキュリティ → **Secret Manager** | シークレット一覧、バージョン |
| GCE | Compute Engine → **VMインスタンス** | インスタンス詳細、ネットワーク、ディスク |
| サービスアカウント | IAMと管理 → **サービスアカウント** | SA一覧、付与ロール |
| IAMロール | IAMと管理 → **IAM** | プロジェクトレベルの権限一覧 |
| ロードバランサー | ネットワークサービス → **ロードバランシング** | LB構成、バックエンド、フロントエンド |
| 外部IPアドレス | VPCネットワーク → **IPアドレス** | 静的IP一覧、使用状況 |
| SSL証明書 | ネットワークサービス → ロードバランシング → **証明書** | 証明書状態（PROVISIONING/ACTIVE） |
| ヘルスチェック | Compute Engine → **ヘルスチェック** | チェック設定、ステータス |
| インスタンスグループ | Compute Engine → **インスタンスグループ** | グループ内インスタンス |
| Cloud Armor | ネットワークセキュリティ → **Cloud Armor ポリシー** | ルール一覧、ログ |
| IAP | セキュリティ → **Identity-Aware Proxy** | SSHトンネル設定 |
| ログ | **Logging** → **Logs Explorer** | Apache/PHP/システムログ検索 |
| メトリクス | **Monitoring** → **Dashboards** | CPU/メモリ/リクエスト数グラフ |
| アラート | **Monitoring** → **Alerting** | アラートポリシー設定 |
| API有効化状態 | **APIとサービス** → **有効なAPIとサービス** | 有効化済みAPI一覧 |

<br>

### 14-10. セットアップ完了後の確認コマンド

```bash
# gcloud
gcloud auth list                    # 認証済みアカウント一覧
gcloud config list                  # プロジェクト・リージョン設定
gcloud projects list                # プロジェクト一覧

# Terraform
terraform --version                 # バージョン確認
cd environments/dev
terraform init                      # 初期化
terraform validate                  # 構文チェック
terraform plan -var="db_password=xxx"  # 実行計画確認

# Ansible
ansible --version                   # バージョン確認
cd ../../ansible
ansible-inventory -i inventory/dev.yml --list  # インベントリ確認
```
