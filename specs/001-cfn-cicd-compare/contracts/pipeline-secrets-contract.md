# Contract: Pipeline Secrets & Trigger Interface

**Feature**: 001-cfn-cicd-compare
**Date**: 2026-02-21

This document defines the required secrets, variables, and trigger conditions for
both pipeline definitions. These are the "interface" that a human operator must
configure once per platform before any pipeline can run.

---

## Required Secrets / Variables

Both pipelines require the same three AWS credential values, stored in their respective
platform secret stores. Values MUST NOT be committed to the repository.

| Secret Name | Description | GitHub Storage | Azure DevOps Storage |
| ----------- | ----------- | -------------- | -------------------- |
| `AWS_ACCESS_KEY_ID` | IAM user access key ID | GitHub → Settings → Secrets → Actions | Variable Group `cfn-practice-secrets` (secret) |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret access key | GitHub → Settings → Secrets → Actions | Variable Group `cfn-practice-secrets` (secret) |
| `AWS_REGION` | Target AWS region | GitHub → Settings → Secrets → Actions | Variable Group `cfn-practice-secrets` (plain) |

**Recommended value for `AWS_REGION`**: `ap-northeast-1`

---

## Pipeline-Internal Variables (not secrets)

These are declared inside the pipeline YAML and can be version-controlled:

| Variable | GitHub Actions | Azure DevOps | Value |
| -------- | -------------- | ------------ | ----- |
| Stack name (GHA) | `env.STACK_NAME` | — | `cfn-practice-gha` |
| Stack name (AzDO) | — | `variables.STACK_NAME` | `cfn-practice-azdo` |
| Template path | `env.TEMPLATE_FILE` | `variables.TEMPLATE_FILE` | `cfn/template.yaml` |

---

## Trigger Conditions

| Event | GitHub Actions | Azure DevOps | Behavior |
| ----- | -------------- | ------------ | -------- |
| Push to `main` | `on: push: branches: [main]` | `trigger: - main` | Full deploy pipeline |
| Push to other branches | Not triggered | Not triggered | No action |
| Manual re-run | GitHub UI → Re-run jobs | Azure DevOps UI → Run pipeline | Full deploy pipeline |

---

## IAM User Minimum Permissions

The IAM user whose credentials are stored as secrets MUST have at minimum the following
AWS permissions. A reference policy document is provided at
`contracts/iam-policy-reference.json`.

**CloudFormation** (scoped to both stacks):

- `cloudformation:CreateChangeSet`
- `cloudformation:DescribeChangeSet`
- `cloudformation:ExecuteChangeSet`
- `cloudformation:DeleteChangeSet`
- `cloudformation:DescribeStacks`
- `cloudformation:DescribeStackEvents`
- `cloudformation:ValidateTemplate`
- `cloudformation:GetTemplate`

**EC2 / VPC** (for resource provisioning):

- `ec2:CreateVpc`, `ec2:DeleteVpc`, `ec2:DescribeVpcs`
- `ec2:CreateSubnet`, `ec2:DeleteSubnet`, `ec2:DescribeSubnets`
- `ec2:CreateInternetGateway`, `ec2:DeleteInternetGateway`, `ec2:AttachInternetGateway`, `ec2:DetachInternetGateway`
- `ec2:CreateRouteTable`, `ec2:DeleteRouteTable`, `ec2:CreateRoute`, `ec2:DeleteRoute`
- `ec2:AssociateRouteTable`, `ec2:DisassociateRouteTable`
- `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:DescribeSecurityGroups`
- `ec2:AuthorizeSecurityGroupEgress`, `ec2:RevokeSecurityGroupEgress`
- `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:DescribeInstances`
- `ec2:CreateTags`, `ec2:DescribeTags`
- `ec2:DescribeAvailabilityZones`, `ec2:DescribeImages`

**SSM** (for dynamic AMI resolution via `{{resolve:ssm:...}}`):

- `ssm:GetParameters` on `arn:aws:ssm:*::parameter/aws/service/ami-amazon-linux-latest/*`

---

## deploy.sh Script Interface

Both pipelines call `scripts/pipeline/deploy.sh` with the following environment
variables pre-set:

| Variable | Set By | Description |
| -------- | ------- | ----------- |
| `AWS_ACCESS_KEY_ID` | Pipeline secret | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | Pipeline secret | IAM user secret key |
| `AWS_REGION` | Pipeline secret | Target region |
| `STACK_NAME` | Pipeline YAML variable | Stack to create/update |
| `TEMPLATE_FILE` | Pipeline YAML variable | Path to CF template |

**Script exit codes**:

| Exit Code | Meaning |
| --------- | ------- |
| `0` | Success (deployment applied, or no changes detected) |
| `1` | Failure (lint error, validation error, change set error, stack update failed) |
