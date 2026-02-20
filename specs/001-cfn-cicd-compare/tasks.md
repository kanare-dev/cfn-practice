# Tasks: CloudFormation CI/CD Platform Comparison

**Input**: Design documents from `/specs/001-cfn-cicd-compare/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅

**Organization**: Tasks grouped by user story (US1–US4) for independent implementation and testing.
No test tasks generated — cfn-lint + pipeline E2E run IS the test suite for this IaC project
(see plan.md Complexity Tracking for justification).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US4)
- Exact file paths are included in every task description

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create directory skeleton and shared tooling configuration

- [x] T001 Create directory structure: `cfn/`, `scripts/pipeline/`, `.github/workflows/`, `.azure/pipelines/`, `docs/`
- [x] T002 [P] Create `.cfnlintrc.yaml` at repo root specifying `regions: [ap-northeast-1]` and `templates: [cfn/template.yaml]` (ensures cfn-lint uses the correct region for AMI and AZ validation)
- [x] T003 [P] Create `specs/001-cfn-cicd-compare/contracts/iam-policy-reference.json` containing a least-privilege IAM policy with all CloudFormation, EC2/VPC, and SSM permissions listed in `specs/001-cfn-cicd-compare/contracts/pipeline-secrets-contract.md`

---

## Phase 2: Foundational (CloudFormation Template)

**Purpose**: The CF template is the single source of truth shared by both pipelines. Must exist and pass lint before any pipeline can be written or tested.

**⚠️ CRITICAL**: No pipeline work begins until `cfn-lint cfn/template.yaml` produces zero ERRORs

- [x] T004 Create `cfn/template.yaml` with all resources per `specs/001-cfn-cicd-compare/data-model.md`: Parameters (`Environment` String default `dev`, `InstanceType` String default `t3.micro`); Networking resources (VPC `10.0.0.0/16` with DNS enabled, InternetGateway, VPCGatewayAttachment, PublicSubnetA `10.0.1.0/24` AZ index 0 MapPublicIpOnLaunch true, PublicSubnetC `10.0.2.0/24` AZ index 1, PrivateSubnetA `10.0.11.0/24` AZ index 0, PrivateSubnetC `10.0.12.0/24` AZ index 1); Route Tables (PublicRouteTable, PublicRoute `0.0.0.0/0` → IGW, PublicSubnetARouteAssoc, PublicSubnetCRouteAssoc, PrivateRouteTable with no internet route, PrivateSubnetARouteAssoc, PrivateSubnetCRouteAssoc); Compute (EC2SecurityGroup with no inbound rules, EC2Instance in PrivateSubnetA using SSM dynamic AMI reference `{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64}}`); Outputs (VPCId, PublicSubnetAId, PublicSubnetCId, PrivateSubnetAId, PrivateSubnetCId, EC2InstanceId)

**Checkpoint**: Run `cfn-lint cfn/template.yaml` locally — must produce zero ERRORs before proceeding to any pipeline phase

---

## Phase 3: User Story 1 - Automated Deployment via GitHub Actions (Priority: P1) 🎯 MVP

**Goal**: A push to GitHub main containing a `cfn/**` change triggers the Actions pipeline,
which validates the template, creates a Change Set, and deploys the CF stack — all without
touching the AWS Console.

**Independent Test**: Push any change under `cfn/` to GitHub `main`. Go to the repository's
Actions tab, open the most recent workflow run, and confirm: all steps green, the
`cfn-practice-gha` stack in ap-northeast-1 shows `CREATE_COMPLETE` or `UPDATE_COMPLETE`.

### Implementation for User Story 1

- [x] T005 [US1] Create `scripts/pipeline/deploy.sh` implementing the 7-step deploy flow (make file executable with `chmod +x`): **(1)** run `cfn-lint $TEMPLATE_FILE` — exit 1 on ERROR; **(2)** run `aws cloudformation validate-template --template-body file://$TEMPLATE_FILE` — exit 1 on failure; **(3)** detect stack: call `aws cloudformation describe-stacks --stack-name $STACK_NAME`, if stack does not exist set `CHANGESET_TYPE=CREATE` and `WAIT_COMMAND=stack-create-complete`, else set `CHANGESET_TYPE=UPDATE` and `WAIT_COMMAND=stack-update-complete`; **(4)** create change set: `aws cloudformation create-change-set --stack-name $STACK_NAME --template-body file://$TEMPLATE_FILE --change-set-name ${STACK_NAME}-$(date +%s) --change-set-type $CHANGESET_TYPE --capabilities CAPABILITY_IAM` and capture the change set name; **(5)** poll change set status in a loop (5 s sleep) until status is `CREATE_COMPLETE` or `FAILED`; **(6)** execute: `aws cloudformation execute-change-set --change-set-name $CHANGESET_NAME --stack-name $STACK_NAME`; **(7)** wait: `aws cloudformation wait $WAIT_COMMAND --stack-name $STACK_NAME` — exit 1 on failure. Script reads `STACK_NAME`, `TEMPLATE_FILE`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` from environment. Exit 0 = success, exit 1 = failure.
- [x] T006 [US1] Create `.github/workflows/deploy.yml`: trigger `on: push: branches: [main]` with `paths: ['cfn/**', '.github/workflows/**']`; single job `deploy` on `ubuntu-latest`; steps: (a) `actions/checkout@v4`, (b) `aws-actions/configure-aws-credentials@v4` with `aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}`, `aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}`, `aws-region: ${{ secrets.AWS_REGION }}`; (c) install cfn-lint: `pip install cfn-lint`; (d) run deploy script: `bash scripts/pipeline/deploy.sh` with env `STACK_NAME: cfn-practice-gha` and `TEMPLATE_FILE: cfn/template.yaml`

**Checkpoint**: Push a `cfn/template.yaml` change to GitHub → Actions tab shows successful run → `cfn-practice-gha` stack exists in ap-northeast-1

---

## Phase 4: User Story 2 - Pre-Deploy Change Visibility (Priority: P2)

**Goal**: Before any change is applied, the pipeline log shows a formatted table listing every
affected resource (action, type, logical ID, replacement flag). An empty Change Set exits
successfully without deploying.

**Independent Test**: Change `InstanceType` default in `cfn/template.yaml` from `t3.micro` to
`t3.small` and push to GitHub `main`. Confirm the log shows a table row:
`Modify | AWS::EC2::Instance | EC2Instance | False` before the execute step. Then revert the
change and push again — confirm pipeline exits 0 with a "no changes" message and no deploy.

### Implementation for User Story 2

- [x] T007 [US2] Add Change Set display step to `scripts/pipeline/deploy.sh` (insert between poll step and execute step): after status reaches `CREATE_COMPLETE`, call `aws cloudformation describe-change-set --change-set-name $CHANGESET_NAME --stack-name $STACK_NAME`, parse `.Changes[].ResourceChange` with `jq`, and print a formatted table to stdout with header `Action | ResourceType | LogicalResourceId | Replacement` followed by one row per change
- [x] T008 [US2] Add empty Change Set handling to `scripts/pipeline/deploy.sh` (inside the poll loop, when status is `FAILED`): check if `StatusReason` contains `"didn't contain changes"` — if so, delete the change set (`aws cloudformation delete-change-set --change-set-name $CHANGESET_NAME --stack-name $STACK_NAME`), print "No changes detected — stack is up to date", and exit 0; for any other FAILED reason, print the StatusReason and exit 1

**Checkpoint**: Push a resource-modifying change → log shows table before execute step; push a description-only change → pipeline exits 0 with "No changes" message

---

## Phase 5: User Story 3 - Failure Investigation and Recovery (Priority: P3)

**Goal**: When a stack update fails, CloudFormation FAILED event details appear in the pipeline
log. If the stack reaches `ROLLBACK_COMPLETE`, the pipeline prints the manual recovery command
and exits with an error.

**Independent Test**: Set `InstanceType` to an invalid type (e.g., `t1.invalid`) in
`cfn/template.yaml` (this passes cfn-lint but fails at AWS). Push to GitHub `main`. Confirm
the pipeline log shows the FAILED event reason, the stack auto-rolls back, and a subsequent
corrected push deploys successfully without manual console steps.

### Implementation for User Story 3

- [x] T009 [US3] Add stack event logging to `scripts/pipeline/deploy.sh` (in the wait failure handler): after `aws cloudformation wait $WAIT_COMMAND` exits non-zero, call `aws cloudformation describe-stack-events --stack-name $STACK_NAME` and filter events where `ResourceStatus` ends in `_FAILED`; print each matching event's `LogicalResourceId`, `ResourceStatus`, and `ResourceStatusReason` to stdout, then exit 1
- [x] T010 [US3] Add `ROLLBACK_COMPLETE` detection to `scripts/pipeline/deploy.sh` (in the stack detection step, before change set creation): if `describe-stacks` returns stack status `ROLLBACK_COMPLETE`, print an error message explaining the stack must be deleted manually, print the recovery command (`aws cloudformation delete-stack --stack-name $STACK_NAME --region $AWS_REGION`), and exit 1

**Checkpoint**: Push invalid InstanceType → log shows FAILED event reason → stack in `UPDATE_ROLLBACK_COMPLETE` → fix and push → deployment succeeds

---

## Phase 6: User Story 4 - Azure DevOps Pipeline Parity (Priority: P4)

**Goal**: The same CF template and `deploy.sh` script are driven from Azure Pipelines,
producing the same end-to-end outcome — validate → Change Set preview → deploy — so that
concrete behavioral differences between the two platforms can be observed and documented.

**Independent Test**: Push the same `cfn/template.yaml` change to the `azdevops` remote.
Confirm Azure Pipelines triggers, the run completes, and the `cfn-practice-azdo` stack in
ap-northeast-1 reaches the same state as `cfn-practice-gha`. Observe and note at least 3
differences in pipeline behavior vs the GitHub Actions run.

### Implementation for User Story 4

- [x] T011 [US4] Create `.azure/pipelines/deploy.yml`: trigger `trigger: branches: include: [main]` with `paths: include: [cfn/*, .azure/pipelines/*]`; single stage/job on `ubuntu-latest` pool; Variable Group reference (`group: cfn-practice-secrets`) under `variables:`; steps: (a) checkout, (b) install cfn-lint (`pip install cfn-lint`), (c) run `scripts/pipeline/deploy.sh` with environment variables: `STACK_NAME: cfn-practice-azdo`, `TEMPLATE_FILE: cfn/template.yaml`, `AWS_ACCESS_KEY_ID: $(AWS_ACCESS_KEY_ID)`, `AWS_SECRET_ACCESS_KEY: $(AWS_SECRET_ACCESS_KEY)`, `AWS_REGION: $(AWS_REGION)`

**Checkpoint**: Push to `azdevops` remote → Azure Pipelines run completes → `cfn-practice-azdo` stack exists in ap-northeast-1 with all resources

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Comparison documentation and final end-to-end validation

- [x] T012 [P] Create `docs/comparison.md` with the blank observation table required by SC-004 — include column headers (Observation Point | GitHub Actions | Azure DevOps) and rows for at least 5 areas: (1) credential/auth setup UX, (2) pipeline YAML syntax and structure, (3) secrets/variable reference syntax, (4) Change Set log quality and visibility, (5) failure message clarity and recovery behavior; leave cell content blank for post-run completion
- [ ] T013 Run the `specs/001-cfn-cicd-compare/quickstart.md` validation checklist end-to-end: verify `cfn-practice-gha` and `cfn-practice-azdo` stacks both exist with `CREATE_COMPLETE`; verify Change Set table appears in both platform logs; verify a no-op push exits 0 without deploying; verify a failing deploy surfaces CF events in the log; verify stack auto-rollback completes and a corrected push succeeds on both platforms; fill in `docs/comparison.md` with observed differences

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (directories must exist)
- **US1 (Phase 3)**: Depends on Phase 2 (CF template must pass cfn-lint before pipeline is written)
- **US2 (Phase 4)**: Depends on Phase 3 (enhances `deploy.sh` created in T005)
- **US3 (Phase 5)**: Depends on Phase 4 (further enhances `deploy.sh`; US2 changes must be in place)
- **US4 (Phase 6)**: Depends on US1 at minimum (`deploy.sh` must exist); recommended to start after US3 so Azure pipeline calls the fully-featured script
- **Polish (Phase 7)**: Depends on Phase 6 (both pipelines must be running)

### User Story Dependencies

- **US1**: Depends on Foundational phase only
- **US2**: Depends on US1 — modifies `deploy.sh` created in T005
- **US3**: Depends on US2 — further modifies `deploy.sh`; US3 can be developed alongside US2 (different sections of the same file) but must be integrated sequentially
- **US4**: Depends on US1 minimum; `.azure/pipelines/deploy.yml` (T011) can be drafted in parallel with US2/US3 since it is a separate file; final validation (US4 checkpoint) requires fully-featured `deploy.sh` from US3

### Within Each User Story

- T005 before T006 — deploy.sh interface must be defined before the GitHub Actions workflow calls it
- T007 before T008 in US2 — display step is inserted first; empty-check modifies adjacent logic
- T009 before T010 in US3 — failure logging added first; ROLLBACK_COMPLETE check is in an earlier code block

### Parallel Opportunities

- T002 and T003 (Phase 1) — independent files, run together
- T011 (Azure pipeline YAML) can be drafted in parallel with US2/US3 deploy.sh enhancements (different files)
- T012 (comparison doc) can be created any time after Phase 3 is verified

---

## Parallel Example: Phase 1

```bash
# Run simultaneously (independent files):
# Task: Create .cfnlintrc.yaml
# Task: Create contracts/iam-policy-reference.json
```

## Parallel Example: US4 + US2/US3

```bash
# T011 (.azure/pipelines/deploy.yml) can be drafted while:
# T007 (changeset display in deploy.sh) and
# T008 (empty changeset handling in deploy.sh) are being written
# Final Azure Pipelines validation waits for the completed deploy.sh
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T003)
2. Complete Phase 2: Foundational (T004 — cfn/template.yaml)
3. Complete Phase 3: US1 (T005–T006 — deploy.sh + GitHub Actions pipeline)
4. **STOP and VALIDATE**: Push to GitHub → confirm `cfn-practice-gha` stack deployed
5. Proceed to US2 → US3 → US4 incrementally

### Incremental Delivery

1. Setup + Foundational → CF template passes cfn-lint
2. US1 → GitHub Actions deploying end-to-end → **MVP validated**
3. US2 → Change Set table visible + empty-changeset handling → **validated with InstanceType change**
4. US3 → Failure events in log + ROLLBACK_COMPLETE guard → **validated with invalid config**
5. US4 → Azure Pipelines deploying same stack → **validated with push to azdevops remote**
6. Polish → Comparison doc filled in, quickstart checklist complete

### `deploy.sh` Enhancement Sequence

All four user stories share a single script. It is built in layers:

| Phase | Adds to deploy.sh |
| ----- | ----------------- |
| US1 (T005) | Steps 1–5, 7–8: lint, validate, detect, create changeset, poll, execute, wait |
| US2 (T007) | Step 6: changeset display table (inserted between poll and execute) |
| US2 (T008) | Empty changeset detection (inside poll loop) |
| US3 (T009) | Failure event logging (in wait failure handler) |
| US3 (T010) | ROLLBACK_COMPLETE guard (in detect step) |
| US4 (T011) | No deploy.sh changes — adds only `.azure/pipelines/deploy.yml` |

---

## Notes

- [P] tasks = different files, no dependency on incomplete tasks
- No TDD test tasks — cfn-lint + pipeline E2E run is the complete test strategy (see plan.md)
- Delete stacks when not actively testing to avoid ongoing EC2 cost (~¥3–4/day × 2 stacks)
- Commit after each task or checkpoint
- `jq` is available on `ubuntu-latest` runners; no additional installation needed for JSON parsing in deploy.sh
