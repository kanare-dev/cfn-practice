# CI/CD Platform Comparison: GitHub Actions vs Azure DevOps

**Feature**: CloudFormation IaC CI/CD
**Template**: `cfn/template.yaml` (single source of truth)
**Stacks**: `cfn-practice-gha` (GitHub Actions) / `cfn-practice-azdo` (Azure Pipelines)
**Date**: _Fill in after completing both pipeline runs_

---

## Overview

This document records first-hand observations from running the same CloudFormation
deployment workflow on both CI/CD platforms. Fill in each cell after completing the
steps in `specs/001-cfn-cicd-compare/quickstart.md`.

---

## Comparison Table

| Observation Point | GitHub Actions | Azure DevOps |
| ----------------- | -------------- | ------------ |
| **1. Credential / auth setup UX** | リポジトリ Settings → Secrets → Actions に登録。手順3ステップ。 | Pipelines → Library → Variable Group を作成し変数を登録。パイプライン側からグループを参照する追加設定が必要。手順が多い。 |
| **2. Pipeline YAML syntax and structure** | `on:` / `jobs:` / `steps:` の3階層。`uses:` でMarketplaceアクションを参照。 | `trigger:` / `pool:` / `steps:` の構造。アクション概念なし、`script:` に直接コマンドを書く。`displayName:` でステップ名を指定。 |
| **3. Secrets / variable reference syntax** | シークレット: `${{ secrets.NAME }}`、変数: `${{ env.NAME }}` | シークレット・変数ともに `$(NAME)`。Variable Groupで一括管理。 |
| **4. Change Set log visibility** | Step 6/7 ヘッダーつきでテーブル表示。整形されて読みやすい。行幅次第で折り返しあり。 | _要実機確認_ |
| **5. Failure message clarity** | _要実機確認_ | _要実機確認_ |
| **6. Re-run / retry mechanism** | 失敗ジョブの「Re-run failed jobs」ボタン。同一コミットで即再実行可能。 | 失敗パイプラインの「Re-run failed stages」。ステージ単位で再試行可能。 |
| **7. Pipeline execution time (first create)** | 1m 46s | _要実機確認_ |
| **8. Pipeline execution time (no-change push)** | 40s（ただしバグにより exit 1。修正後に再計測） | _要実機確認_ |
| **9. Live run monitoring UI** | ステップ単位でリアルタイムログを展開表示。Step Summaryパネルで構造化出力が可能。 | ステップ単位でログを確認可能。Step Summaryに相当する構造化出力パネルはない。 |
| **10. Path filter trigger syntax** | `paths: ['cfn/**', '.github/workflows/**']`（`**` 再帰グロブ対応） | `paths.include: ['cfn/*', '.azure/pipelines/*']`（`*` 単一階層のみ） |
| **11. ホステッドランナーの初期利用** | 即時利用可能（無料枠あり） | 新規組織はホステッド並列実行の申請が必要（承認まで2〜3営業日） |

---

## Detailed Notes

### 1. Credential / Auth Setup UX

**GitHub Actions**:

> リポジトリ単位で管理。Settings → Secrets and variables → Actions → New repository secret。
> Key/Value を入力するだけで完了。登録後は値を再表示できない（上書きのみ）。
> パイプラインYAMLから `${{ secrets.NAME }}` で参照するだけで使える。

**Azure DevOps**:

> Pipelines → Library → + Variable group でグループを作成。
> 変数を追加し、シークレットにしたい変数は鍵アイコンをクリックして「Secret」にする。
> パイプラインYAML側で `variables: - group: cfn-practice-secrets` を宣言してグループを紐付け、
> 各ステップの `env:` ブロックで `VAR: $(VAR)` と明示的に渡す必要がある。

---

### 2. Pipeline YAML Syntax and Structure

**GitHub Actions** (`.github/workflows/deploy.yml`):

```yaml
on:                        # トリガー定義
  push:
    branches: [main]
    paths: ['cfn/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4         # Marketplaceアクション
      - uses: aws-actions/configure-aws-credentials@v4
      - run: bash scripts/pipeline/deploy.sh
        env:
          STACK_NAME: cfn-practice-gha
```

**Azure DevOps** (`.azure/pipelines/deploy.yml`):

```yaml
trigger:                   # トリガー定義
  branches:
    include: [main]
  paths:
    include: [cfn/*]

variables:
  - group: cfn-practice-secrets   # Variable Group参照
  - name: STACK_NAME
    value: cfn-practice-azdo

pool:
  vmImage: ubuntu-latest

steps:
  - checkout: self
  - script: bash scripts/pipeline/deploy.sh   # 直接コマンド記述
    displayName: Deploy CloudFormation Stack
    env:
      STACK_NAME: $(STACK_NAME)
      AWS_ACCESS_KEY_ID: $(AWS_ACCESS_KEY_ID)
```

Key syntactic differences observed:

- GitHub Actionsは `uses:` でMarketplaceアクション（`configure-aws-credentials`）を利用できる。Azure DevOpsにはアクション概念がなく、AWS CLI設定は `env:` 経由で手動で行う。
- GitHub Actionsのトリガーは `on:` キー。Azure DevOpsは `trigger:` キー。
- Azure DevOpsはランナーを `pool: vmImage:` で指定。GitHub Actionsは `runs-on:` で指定。

---

### 3. Secrets / Variable Reference Syntax

| | GitHub Actions | Azure DevOps |
| --- | --- | --- |
| Secret reference | `${{ secrets.NAME }}` | `$(NAME)` |
| Variable reference | `${{ env.NAME }}` | `$(NAME)` |
| Variable Group | N/A（概念なし） | `group: cfn-practice-secrets` |
| Passing to script env | `env:` block under step | `env:` block under `script:` step |

Additional notes:

> GitHub Actionsはシークレットと通常変数で参照構文が異なる（`secrets.` vs `env.`）が、
> Azure DevOpsはどちらも `$(NAME)` で統一されている。
> Azure DevOpsのVariable Groupはクロスプロジェクト共有も可能（このプロジェクトでは不使用）。

---

### 4. Change Set Log Visibility

**GitHub Actions**:

> `── Step 6/7: Change Set contents ──` というヘッダーつきで表示される。
> テーブル形式（`Action | ResourceType | LogicalResourceId | Replacement`）が
> ログ上でも整形されて読みやすい。全リソースが1行ずつ列挙され、初回CREATE時は全行 `Add`。
>
> 1点注意: ログの行幅が狭い環境では行が折り返されて1行が2行に分割されることがある
> （今回の実行で `PrivateSubnetCRouteAssoc` の行が折り返されて表示が乱れた）。
> ただし内容の読み取り自体は問題なし。

**Azure DevOps**:

> _要実機確認: Azure Pipelinesのログでの表示位置を確認_
> _Note: Azure DevOps does not have a GitHub-style Step Summary panel._

---

### 5. Failure Message Clarity

**Scenario**: Push a deliberately broken configuration (e.g., invalid InstanceType).

**GitHub Actions**:

> _要実機確認: ログに出るFAILEDイベントの内容を記録_

**Azure DevOps**:

> _要実機確認: Azure Pipelinesでの失敗ログを記録_

Which platform made the failure reason easier to find?

> _要実機確認_

---

### 6. Re-run / Retry Mechanism

**GitHub Actions**:

> 失敗したジョブのページで「Re-run failed jobs」ボタンをクリック。
> 同一コミットに対して再実行される（新しいコミットは不要）。
> 「Re-run all jobs」で成功済みのステップも含めて全体再実行も可能。

**Azure DevOps**:

> 失敗したパイプライン実行ページで「Re-run failed stages」が利用可能。
> ステージ単位での再試行が可能。同一コミットに対して再実行される。

---

### 7. Pipeline Execution Time

Fill in after both platforms complete a first-time stack CREATE:

| Scenario | GitHub Actions | Azure DevOps |
| --- | --- | --- |
| First stack create (full) | 1m 46s | _要実機確認_ |
| Stack update (resource change) | _min_ | _min_ |
| No-change push (empty changeset) | 約40s（バグ修正後に再計測） | _要実機確認_ |

---

### 9. Live Run Monitoring UI

**GitHub Actions**:

> ワークフロー実行ページでジョブ → ステップをクリックするとリアルタイムでログが展開される。
> `$GITHUB_STEP_SUMMARY` に書き込むとStep Summaryパネルに構造化出力が表示できる（このプロジェクトでは未使用）。

**Azure DevOps**:

> パイプライン実行ページでステップをクリックするとログを確認できる。
> Step Summaryに相当する構造化出力パネルはない。ログはフラットなテキスト出力のみ。

---

### 10. Path Filter Trigger Syntax

**GitHub Actions**:
```yaml
on:
  push:
    paths:
      - 'cfn/**'               # ** で再帰的にマッチ
      - '.github/workflows/**'
```

**Azure DevOps**:
```yaml
trigger:
  paths:
    include:
      - cfn/*                  # * は単一階層のみ（再帰なし）
      - .azure/pipelines/*
```

> GitHub Actionsの `**` は任意の深さのサブディレクトリにマッチするが、
> Azure DevOpsの `*` は単一階層のみ。ネストしたファイルを対象にする場合は注意が必要。

---

### 11. ホステッドランナーの初期利用

**GitHub Actions**:

> パブリック・プライベートリポジトリともに、リポジトリ作成後すぐにホステッドランナー（ubuntu-latest）が利用可能。
> 追加の申請・設定は不要。

**Azure DevOps**:

> 新規組織ではホステッド並列実行（Microsoft-hosted agents）がデフォルトで無効。
> 以下のフォームから無料枠の申請が必要で、承認まで2〜3営業日かかる。
> `https://aka.ms/azpipelines-parallelism-request`
>
> 申請が承認されるまでのワークアラウンドとして、自前PCをセルフホステッドエージェントとして登録する方法もある。

---

### 8. Overall Assessment

After running both platforms through the full quickstart sequence
(`specs/001-cfn-cicd-compare/quickstart.md` Steps 4–7), summarize:

**GitHub Actions** — strengths / weaknesses for CloudFormation CI/CD:

>

**Azure DevOps** — strengths / weaknesses for CloudFormation CI/CD:

>

**Recommendation** for a solo IaC practitioner:

>

---

## Checklist (complete before marking SC-004 done)

- [x] GitHub Actions で初回デプロイ成功
- [ ] Azure DevOps で初回デプロイ成功
- [ ] Change Set table visible in both platform logs (Step 6 test)
- [ ] Empty changeset exits 0 on both platforms (Step 6 no-change push)
- [ ] Failure reason visible in both platform logs (Step 7 test)
- [ ] Stack auto-rollback confirmed on both platforms
- [ ] Corrected push succeeds after rollback on both platforms
- [ ] All 5 mandatory comparison rows filled in (rows 1–5)
- [ ] Comparison committed to `docs/comparison.md` on `main`
