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
| **1. Credential / auth setup UX** | | |
| **2. Pipeline YAML syntax and structure** | | |
| **3. Secrets / variable reference syntax** | | |
| **4. Change Set log visibility** | | |
| **5. Failure message clarity** | | |
| **6. Re-run / retry mechanism** | | |
| **7. Pipeline execution time (first create)** | | |
| **8. Pipeline execution time (no-change push)** | | |
| **9. Live run monitoring UI** | | |
| **10. Path filter trigger syntax** | | |

---

## Detailed Notes

### 1. Credential / Auth Setup UX

**GitHub Actions**:

> _Describe the experience of adding secrets in GitHub → Settings → Secrets → Actions_

**Azure DevOps**:

> _Describe the experience of creating the Variable Group `cfn-practice-secrets` in Library_

---

### 2. Pipeline YAML Syntax and Structure

**GitHub Actions** (`.github/workflows/deploy.yml`):

> _Note key YAML constructs: `on:`, `jobs:`, `steps:`, `uses:`, `run:`, `env:`_

**Azure DevOps** (`.azure/pipelines/deploy.yml`):

> _Note key YAML constructs: `trigger:`, `variables:`, `pool:`, `steps:`, `script:`, `env:`_

Key syntactic differences observed:

-
-
-

---

### 3. Secrets / Variable Reference Syntax

| | GitHub Actions | Azure DevOps |
|---|---|---|
| Secret reference | `${{ secrets.NAME }}` | `$(NAME)` |
| Variable reference | `${{ env.NAME }}` | `$(NAME)` |
| Variable Group | N/A (no concept) | `group: cfn-practice-secrets` |
| Passing to script env | `env:` block under step | `env:` block under `script:` step |

Additional notes:

>

---

### 4. Change Set Log Visibility

**GitHub Actions**:

> _Describe where and how the Change Set table appears in the Actions run log._
> _Is it easy to find? Is the table formatting preserved?_

**Azure DevOps**:

> _Describe where the Change Set table appears in the Azure Pipelines log._
> _Note: Azure DevOps does not have a GitHub-style Step Summary panel._

---

### 5. Failure Message Clarity

**Scenario**: Push a deliberately broken configuration (e.g., invalid InstanceType).

**GitHub Actions**:

> _Paste or summarize the failure output visible in the Actions log._

**Azure DevOps**:

> _Paste or summarize the failure output visible in the Azure Pipelines log._

Which platform made the failure reason easier to find?

>

---

### 6. Re-run / Retry Mechanism

**GitHub Actions**:

> _How do you re-run a failed job? (Re-run jobs button in Actions tab)_
> _Does re-run re-checkout the same commit or the latest?_

**Azure DevOps**:

> _How do you re-run a failed pipeline? (Run pipeline button, or retry)_

---

### 7. Pipeline Execution Time

Fill in after both platforms complete a first-time stack CREATE:

| Scenario | GitHub Actions | Azure DevOps |
|----------|----------------|--------------|
| First stack create (full) | min | min |
| Stack update (resource change) | min | min |
| No-change push (empty changeset) | min | min |

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

- [ ] Both stacks deployed successfully at least once
- [ ] Change Set table visible in both platform logs (Step 6 test)
- [ ] Empty changeset exits 0 on both platforms (Step 6 no-change push)
- [ ] Failure reason visible in both platform logs (Step 7 test)
- [ ] Stack auto-rollback confirmed on both platforms
- [ ] Corrected push succeeds after rollback on both platforms
- [ ] All 5 mandatory comparison rows filled in (rows 1–5)
- [ ] Comparison committed to `docs/comparison.md` on `main`
