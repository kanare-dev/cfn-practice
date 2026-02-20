# Quickstart: CloudFormation CI/CD Platform Comparison

**Feature**: 001-cfn-cicd-compare
**Date**: 2026-02-21

This guide walks through the one-time setup required to run both pipelines and explains
what to observe during and after each run.

---

## Prerequisites

- AWS account with permissions to create VPC, EC2, IAM roles, and CloudFormation stacks
- GitHub account with access to `kanare-dev/cfn-practice`
- Azure DevOps organization `kanare-org` with project `cfn-practice`
- AWS CLI installed locally (for one-time IAM user creation verification)

---

## Step 1: Create an IAM User for CI/CD

In the AWS Console or via CLI:

```bash
# Create IAM user
aws iam create-user --user-name cfn-practice-cicd

# Attach an inline policy
# Required actions: cloudformation:*, ec2:* (VPC/subnet/IGW/SG/instance),
# ssm:GetParameters (for AMI dynamic reference)
# No IAM permissions needed — the template creates no IAM resources
aws iam put-user-policy \
  --user-name cfn-practice-cicd \
  --policy-name cfn-practice-deploy \
  --policy-document file://contracts/iam-policy-reference.json

# Create access key
aws iam create-access-key --user-name cfn-practice-cicd
```

Save the `AccessKeyId` and `SecretAccessKey` — you will need them in Steps 2 and 3.

---

## Step 2: Configure GitHub Secrets

1. Go to `https://github.com/kanare-dev/cfn-practice`
2. Settings → Secrets and variables → Actions → New repository secret
3. Add three secrets:
   - `AWS_ACCESS_KEY_ID` — from Step 1
   - `AWS_SECRET_ACCESS_KEY` — from Step 1
   - `AWS_REGION` — `ap-northeast-1`

---

## Step 3: Configure Azure DevOps Variable Group

1. Go to `https://dev.azure.com/kanare-org/cfn-practice`
2. Pipelines → Library → + Variable group
3. Name: `cfn-practice-secrets`
4. Add three variables:
   - `AWS_ACCESS_KEY_ID` — from Step 1 (click lock icon to mark as secret)
   - `AWS_SECRET_ACCESS_KEY` — from Step 1 (mark as secret)
   - `AWS_REGION` — `ap-northeast-1` (plain)
5. Save

---

## Step 4: First Deployment — GitHub Actions

Trigger by pushing any change to `main` on GitHub:

```bash
# Make a trivial change (e.g., add a Description to the template)
# then push to main
git push github main
```

**What to observe in GitHub Actions**:

1. Go to the repository → Actions tab → most recent workflow run
2. **Lint step**: cfn-lint output — should show no ERRORs
3. **Validate step**: `aws cloudformation validate-template` output
4. **Create Change Set step**: Change set name logged
5. **Display Change Set step**: Table showing resources to be created (all Add on first run)
6. **Execute / Wait step**: Stack creation in progress
7. **Final status**: `CREATE_COMPLETE` in the log

**Expected duration**: 8–12 minutes (first-time VPC + NAT Gateway creation)

---

## Step 5: First Deployment — Azure DevOps

Trigger by pushing any change to `main` on Azure DevOps:

```bash
git push azdevops main
```

**What to observe in Azure DevOps**:

1. Go to `https://dev.azure.com/kanare-org/cfn-practice` → Pipelines → most recent run
2. Compare each step name and log format against the GitHub Actions run
3. Note: Azure DevOps does not have a native Step Summary panel — change set output
   is visible directly in the script log

---

## Step 6: Test Change Visibility (User Story 2)

Make a modification to the CloudFormation template that changes a resource property:

```bash
# Edit cfn/template.yaml — change InstanceType default from t3.micro to t3.small
# This changes the EC2 instance (Modify, no replacement)
git add cfn/template.yaml
git commit -m "test: change InstanceType to t3.small for change-set visibility test"
git push github main && git push azdevops main
```

**What to observe**: The Change Set table should show:
- `Modify | EC2Instance | AWS::EC2::Instance | False` (no replacement)

---

## Step 7: Test Failure Recovery (User Story 3)

Intentionally break the template to trigger a deployment failure:

```bash
# Edit cfn/template.yaml — add an invalid property to EC2Instance
# e.g., add "InvalidProperty: true" under EC2Instance Properties
# cfn-lint will catch this before AWS is ever called
```

To trigger a runtime failure (passes lint but fails during stack update), set an
instance type that doesn't exist in ap-northeast-1:

```yaml
# In cfn/template.yaml Parameters section:
InstanceType:
  Default: t1.invalid-type
```

**What to observe**:
- The pipeline fails at the Wait step
- `describe-stack-events` output shows the failure reason in the pipeline log
- Stack rolls back automatically to previous state
- Push a fix → pipeline succeeds without manual console intervention

---

## Step 8: Comparison Documentation

After completing Steps 4–7 on both platforms, record observations in a comparison log:

| Observation Point | GitHub Actions | Azure DevOps |
| ----------------- | -------------- | ------------ |
| Credential setup UX | | |
| Pipeline YAML readability | | |
| Variable/secret reference syntax | | |
| Step log visibility (change set) | | |
| Failure message clarity | | |
| Re-run / retry mechanism | | |
| Pipeline execution time | | |
| UI for monitoring live runs | | |

---

## Validation Checklist

Before considering the feature complete, verify:

- [ ] `cfn-practice-gha` stack exists in ap-northeast-1 with status `CREATE_COMPLETE`
- [ ] `cfn-practice-azdo` stack exists in ap-northeast-1 with status `CREATE_COMPLETE`
- [ ] Both stacks show identical resources (VPC, 4 subnets, NAT GW, EC2)
- [ ] A change-producing push shows Change Set table in both pipeline logs
- [ ] A no-change push exits with success (no deployment attempt) on both platforms
- [ ] A failing deployment shows CF stack events in pipeline logs on both platforms
- [ ] Stack auto-rolls back and a corrected push succeeds on both platforms
- [ ] Comparison table (Step 8) has at least 5 rows filled in

---

## Cleanup

To avoid ongoing AWS charges after verification is complete:

```bash
aws cloudformation delete-stack --stack-name cfn-practice-gha --region ap-northeast-1
aws cloudformation delete-stack --stack-name cfn-practice-azdo --region ap-northeast-1

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name cfn-practice-gha --region ap-northeast-1
aws cloudformation wait stack-delete-complete --stack-name cfn-practice-azdo --region ap-northeast-1
```

**Cost note**: The main ongoing cost is the EC2 instance (~$0.0104/hr for t3.micro ×
2 stacks = ~$0.50/day). VPC, subnets, and IGW are free. Delete stacks when not
actively testing.
