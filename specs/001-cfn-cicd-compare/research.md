# Research: CloudFormation CI/CD Platform Comparison

**Feature**: 001-cfn-cicd-compare
**Date**: 2026-02-21
**Phase**: 0 — Outline & Research

---

## Decision 1: CloudFormation Template Format

**Decision**: YAML
**Rationale**: Human-readable, supports inline comments, consistent with industry
conventions for IaC. JSON CloudFormation is syntactically noisier and less suitable
for explanation and comparison documentation.
**Alternatives considered**: JSON — rejected due to readability and lack of comment
support.

---

## Decision 2: GitHub Actions Deployment Method

**Decision**: Direct AWS CLI via create-change-set → execute-change-set, NOT the
`aws-actions/aws-cloudformation-github-deploy` action.

**Rationale**:
- Full visibility into every deployment step (validate → create-change-set →
  describe-change-set → execute-change-set → wait → describe-stack-events on failure)
- Ability to detect and handle empty change sets explicitly (check StatusReason for
  "didn't contain changes")
- Change set contents printed as a table before execution — satisfies FR-003
- Stack events on failure surfaced directly in pipeline logs — satisfies FR-005
- Educational value: each AWS CLI call maps to a specific pipeline step, making the
  comparison with Azure DevOps structurally equivalent

**Alternatives considered**: `aws-actions/aws-cloudformation-github-deploy` — simpler
YAML but hides change set details; not suitable for comparison project where visibility
is a first-class requirement.

---

## Decision 3: Azure DevOps Deployment Method

**Decision**: Direct AWS CLI (same approach as GitHub Actions), NOT the AWS
CloudFormation Deploy task from AWS Toolkit for Azure DevOps.

**Rationale**:
- Keeps both pipelines structurally equivalent → apples-to-apples comparison
- Avoids dependency on marketplace extension availability/versions
- The YAML syntax differences between the two platforms are the subject of comparison;
  the underlying deployment logic (AWS CLI) MUST be identical
- AWS CLI is available on ubuntu-latest agents via pip install

**Alternatives considered**: AWS CloudFormation Deploy task — rejected because it
abstracts deployment details and uses different commands than the GitHub Actions path,
making comparison less meaningful.

---

## Decision 4: AWS Credentials Management

**Decision**: IAM user credentials stored as platform secrets (GitHub Secrets /
Azure DevOps Variable Groups).

**GitHub Actions**: `aws-actions/configure-aws-credentials@v4` with
`aws-access-key-id` and `aws-secret-access-key` inputs.

**Azure DevOps**: Pipeline variables marked as secret in a Variable Group linked to
the pipeline. Credentials exposed as `$(AWS_ACCESS_KEY_ID)` and
`$(AWS_SECRET_ACCESS_KEY)` environment variables.

**Rationale**: OIDC is the recommended production approach but requires creating an
AWS IAM Identity Provider and Role trust policy — extra setup that is out of scope
for this personal verification project. IAM user with minimal permissions is simpler
and equally secure at personal scale.

**Alternatives considered**: OIDC federation — preferred for production; deferred.
AWS Toolkit service connection — tied to the rejected task approach.

---

## Decision 5: Handle First Deploy (CREATE) vs Re-Deploy (UPDATE)

**Decision**: Detect stack existence before creating the change set; use
`--change-set-type CREATE` for new stacks, `UPDATE` for existing ones. Use
`stack-create-complete` or `stack-update-complete` wait accordingly.

**Implementation**:
```bash
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
  CHANGESET_TYPE="UPDATE"
  WAIT_COMMAND="stack-update-complete"
else
  CHANGESET_TYPE="CREATE"
  WAIT_COMMAND="stack-create-complete"
fi
```

**Rationale**: `create-change-set` without `--change-set-type` defaults to UPDATE and
fails on a non-existent stack. Explicit detection avoids this error and selects the
correct wait command.

---

## Decision 6: Empty Change Set Handling

**Decision**: After `create-change-set` wait, check `Status` and `StatusReason`.
If `Status=FAILED` and `StatusReason` contains "didn't contain changes", delete the
change set and exit 0 (success). Any other FAILED reason → exit 1.

**Rationale**: An empty change set is not a failure — it means the infrastructure is
already in the desired state. Satisfies FR-009. The pipeline status must be green in
this case.

---

## Decision 7: Shared Pipeline Logic via Shell Scripts

**Decision**: Extract common AWS CLI logic into `scripts/pipeline/deploy.sh`. Both
pipelines call this script with identical arguments, differing only in how they
install dependencies and pass secrets.

**Rationale**: DRY — any bug fix in the deployment logic is fixed once. The YAML files
for each platform focus on platform-specific syntax (trigger, variable references, step
format), making differences more apparent for comparison. Aligns with Principle I (SRP).

---

## Decision 8: AWS Region

**Decision**: `ap-northeast-1` (Tokyo)
**Rationale**: Lowest latency for the project owner. Standard default for Japanese
AWS practitioners.

---

## Decision 9: EC2 AMI Selection

**Decision**: Dynamic resolution via SSM Parameter Store at stack creation time.
```yaml
ImageId: '{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64}}'
```

**Rationale**: No hardcoded AMI IDs to maintain. Always uses the latest Amazon Linux
2023 AMI for the region. Free-tier eligible with t3.micro.

---

## Decision 10: Stack Names

**Decision**: `cfn-practice-gha` (GitHub Actions stack), `cfn-practice-azdo`
(Azure DevOps stack)

**Rationale**: Separate stacks prevent concurrent-update conflicts (edge case from
spec). Stack name communicates which platform manages it. Both stacks share identical
infrastructure from the same template.

---

## Decision 11: cfn-lint Usage

**Decision**: cfn-lint installed via pip in both pipelines. Run against
`cfn/template.yaml`. Pipeline fails if any ERROR-level finding is reported.
WARNING-level findings are printed but do not block.

**Configuration**: `.cfnlintrc.yaml` at repo root specifying region `ap-northeast-1`
and template include path.

---

## Decision 12: IAM Permissions for CI/CD User

**Required AWS IAM permissions** for the deployment IAM user:
- `cloudformation:*` scoped to `cfn-practice-gha` and `cfn-practice-azdo` stacks
- `ec2:*` (VPC, subnets, IGW, NAT Gateway, EIP, route tables, security groups,
  instances)
- `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`,
  `iam:GetRole`, `iam:PassRole`, `iam:CreateInstanceProfile`,
  `iam:DeleteInstanceProfile`, `iam:AddRoleToInstanceProfile`,
  `iam:RemoveRoleFromInstanceProfile` (for EC2 SSM Instance Profile)
- `ssm:GetParameters` on the AMI parameter path (read-only)

**Note**: A least-privilege IAM policy document will be provided in
`contracts/iam-policy.json`.

---

## Key Platform Differences Identified (Preview)

| Dimension | GitHub Actions | Azure DevOps |
| --------- | -------------- | ------------ |
| Variable ref syntax | `${{ secrets.NAME }}` | `$(NAME)` |
| Secret storage | GitHub Secrets (repo settings) | Variable Group (Library) |
| Step type | `run:` | `script:` |
| Trigger keyword | `on: push:` | `trigger:` |
| Job dependency | `needs:` | `dependsOn:` |
| Conditional | `if:` (expression) | `condition:` (function) |
| Step summary | `$GITHUB_STEP_SUMMARY` | No native equivalent |
| AWS CLI setup | `aws-actions/configure-aws-credentials` action | `pip install awscli` + manual env vars |
