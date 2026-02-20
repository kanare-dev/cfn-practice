# Implementation Plan: CloudFormation CI/CD Platform Comparison

**Branch**: `001-cfn-cicd-compare` | **Date**: 2026-02-21 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-cfn-cicd-compare/spec.md`

---

## Summary

Deploy the same CloudFormation template (multi-AZ VPC + private EC2, no NAT Gateway)
from both GitHub Actions and Azure DevOps, using a shared Bash deploy script driven by
the AWS CLI. Each pipeline validates the template with cfn-lint, creates and displays a
Change Set before applying changes, surfaces CloudFormation stack events on failure, and
handles empty Change Sets gracefully. Two separate stacks (`cfn-practice-gha`,
`cfn-practice-azdo`) in `ap-northeast-1` prevent concurrent-update conflicts.

---

## Technical Context

**Language/Version**: YAML (CloudFormation template, pipeline definitions), Bash 5 (pipeline scripts)
**Primary Dependencies**: AWS CLI v2, cfn-lint ≥ 1.x, aws-actions/configure-aws-credentials@v4 (GitHub Actions only)
**Storage**: N/A — no application database; CloudFormation manages AWS infrastructure state
**Testing**: cfn-lint (template lint), aws cloudformation validate-template (pre-deploy), pipeline run as E2E test
**Target Platform**: GitHub Actions (ubuntu-latest), Azure Pipelines (ubuntu-latest), AWS ap-northeast-1
**Project Type**: single — one repo, two pipeline files, one CF template
**Performance Goals**: Full pipeline (lint → deploy → wait) completes ≤ 15 min; CF stack create ≤ 10 min
**Constraints**: Personal AWS account; IAM user credentials (not OIDC); no approval gates; free-tier EC2 (t3.micro); no NAT Gateway (cost control)
**Scale/Scope**: 1 developer, 2 pipelines, 2 CF stacks, 14 AWS resources per stack

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I — Code Quality

| Gate | Status | Evidence |
| ---- | ------ | -------- |
| Lint/formatting passes before merge | ✅ | cfn-lint gate in both pipelines (blocks deploy on ERROR) |
| Cyclomatic complexity ≤ 10 per function | ✅ | deploy.sh: max 3 nesting levels; no function exceeds complexity 5 |
| SRP enforced | ✅ | deploy.sh handles deployment logic only; pipeline YAML handles platform concerns only |
| Dead code removed | ✅ | No placeholder code in template or scripts |
| Clear naming | ✅ | CF logical IDs (`PrivateSubnetA`, `NatGateway`), script variables (`CHANGESET_TYPE`, `WAIT_COMMAND`) are self-documenting |
| Peer review | ⚠️ | **Deviation** — personal project; documented in Complexity Tracking |

### Principle II — Testing Standards

| Gate | Status | Evidence |
| ---- | ------ | -------- |
| Test-First / Red-Green-Refactor | ⚠️ | **Deviation** — inapplicable to IaC YAML; documented in Complexity Tracking |
| 80% branch coverage | ⚠️ | **Deviation** — no coverage tooling for Bash/YAML; documented in Complexity Tracking |
| Integration tests for cross-component boundaries | ✅ | Pipeline run IS the integration test; Change Set confirms resource-level intent |
| Deterministic tests | ✅ | cfn-lint and validate-template are deterministic; no random data |

### Principle III — User Experience Consistency

| Gate | Status | Evidence |
| ---- | ------ | -------- |
| Error messages identify root cause | ✅ | describe-stack-events surfaces FAILED resource reasons in log (FR-005) |
| Consistent interaction flows | ✅ | Both pipelines follow identical logical steps; step names match across platforms |
| Empty/error states handled explicitly | ✅ | Empty Change Set → delete + exit 0 (FR-009); failure → events logged + exit 1 |
| No silent failures | ✅ | Every failure path exits 1 with an explicit error message |

### Principle IV — Performance Requirements

| Gate | Status | Evidence |
| ---- | ------ | -------- |
| p95 API response ≤ 200 ms | ⚠️ | **Deviation** — no HTTP API; inapplicable; documented in Complexity Tracking |
| Pipeline completes ≤ 15 min | ✅ | SC-001; typical VPC+NAT+EC2 stack: 5–8 min; total pipeline: ~10–12 min |
| Memory regression ≤ 5% | N/A | Pipeline runs in ephemeral CI runners; no persistent memory baseline |
| Performance regression tests in CI | ✅ | Pipeline timing is observable from CI run history; no regression tooling needed for IaC |

---

## Project Structure

### Documentation (this feature)

```text
specs/001-cfn-cicd-compare/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   ├── cfn-template-contract.md
│   └── pipeline-secrets-contract.md
└── tasks.md             # Phase 2 output (/speckit.tasks — not yet created)
```

### Source Code (repository root)

```text
cfn/
└── template.yaml                  # CloudFormation template (single source of truth)

scripts/
└── pipeline/
    └── deploy.sh                  # Shared AWS CLI deploy logic; called by both pipelines

.github/
└── workflows/
    └── deploy.yml                 # GitHub Actions pipeline

.azure/
└── pipelines/
    └── deploy.yml                 # Azure Pipelines definition

.cfnlintrc.yaml                    # cfn-lint configuration (region: ap-northeast-1)
```

**Structure Decision**: Single-project layout. No `src/` — this is IaC, not application
code. Two pipeline directories (`.github/`, `.azure/`) co-exist in one repo so the CF
template is the single source of truth (FR-010). Scripts live in `scripts/pipeline/`
to separate platform-specific YAML from shared deployment logic (Principle I: SRP).

---

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
| --------- | ---------- | ------------------------------------ |
| Principle I: No peer review | Personal project; single developer | N/A — adding a required reviewer would block the solo practitioner workflow this project is designed for |
| Principle II: No TDD / 80% coverage | cfn-lint and YAML are declarative artifacts, not imperative code; no test harness exists for CloudFormation YAML | TDD requires a test runner that executes and asserts behavior; no such tool exists for CF templates without a full stack deployment (which IS the E2E test) |
| Principle II: No coverage tooling | Bash coverage tools (bashcov, kcov) are fragile in CI environments and add setup complexity disproportionate to a 60-line script | Compensating control: deploy.sh has ≤ 4 code paths, all exercised during normal use |
| Principle IV: p95 ≤ 200 ms | No HTTP API in this project | Compensating control: pipeline completion time (≤ 15 min) is the relevant SLA, enforced by SC-001 and observable in CI run history |
