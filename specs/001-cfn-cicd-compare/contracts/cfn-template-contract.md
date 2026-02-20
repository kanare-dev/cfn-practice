# Contract: CloudFormation Template Interface

**Feature**: 001-cfn-cicd-compare
**Date**: 2026-02-21

This document defines the stable interface of `cfn/template.yaml`. Both pipelines
MUST pass these inputs and can consume these outputs.

---

## Inputs (Parameters)

| Parameter | Type | Allowed Values | Default | Required |
| --------- | ---- | -------------- | ------- | -------- |
| `Environment` | String | `dev`, `stg`, `prod` | `dev` | No |
| `InstanceType` | String | Any valid EC2 type | `t3.micro` | No |

Both pipelines invoke the template with no parameter overrides for this verification
project (defaults are sufficient).

---

## Outputs (Stack Exports)

| Output Key | Description | Consumer |
| ---------- | ----------- | -------- |
| `VPCId` | ID of the created VPC | Post-deploy verification |
| `PublicSubnetAId` | Public subnet in first AZ | Post-deploy verification |
| `PublicSubnetCId` | Public subnet in second AZ | Post-deploy verification |
| `PrivateSubnetAId` | Private subnet in first AZ (EC2 lives here) | Post-deploy verification |
| `PrivateSubnetCId` | Private subnet in second AZ | Post-deploy verification |
| `EC2InstanceId` | ID of the EC2 instance in private subnet | Post-deploy verification |

---

## Required Capabilities

No `--capabilities` flag is required. The template does not create any IAM resources.

---

## Breaking Change Policy

Any change to the template that causes a resource **Replacement** (Replacement=True in
Change Set) is considered a breaking change and MUST be visible in the Change Set
review before execution. The pipeline enforces this automatically by printing the Change
Set table before executing.

Changes that are safe (no replacement):
- Modifying Tags
- Updating UserData (in most cases)
- Changing Security Group rules

Changes that replace resources (MUST be reviewed):
- Changing subnet assignment of EC2
- Changing VPC CIDR blocks
- Changing Security Group VPC association
