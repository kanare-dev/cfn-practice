# Data Model: CloudFormation CI/CD Platform Comparison

**Feature**: 001-cfn-cicd-compare
**Date**: 2026-02-21
**Phase**: 1 — Design

---

## CloudFormation Template Structure

**File**: `cfn/template.yaml`

### Parameters

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |
| `Environment` | String | `dev` | Environment tag applied to all resources |
| `InstanceType` | String | `t3.micro` | EC2 instance type for the private instance |

### Resources

#### Networking Layer

| Logical ID | Type | Key Properties |
| ---------- | ---- | -------------- |
| `VPC` | `AWS::EC2::VPC` | CidrBlock: `10.0.0.0/16`, DNS enabled |
| `InternetGateway` | `AWS::EC2::InternetGateway` | — |
| `VPCGatewayAttachment` | `AWS::EC2::VPCGatewayAttachment` | Attaches IGW to VPC |
| `PublicSubnetA` | `AWS::EC2::Subnet` | `10.0.1.0/24`, AZ index 0, MapPublicIpOnLaunch: true |
| `PublicSubnetC` | `AWS::EC2::Subnet` | `10.0.2.0/24`, AZ index 1, MapPublicIpOnLaunch: true |
| `PrivateSubnetA` | `AWS::EC2::Subnet` | `10.0.11.0/24`, AZ index 0 |
| `PrivateSubnetC` | `AWS::EC2::Subnet` | `10.0.12.0/24`, AZ index 1 |

#### Route Tables

| Logical ID | Type | Key Properties |
| ---------- | ---- | -------------- |
| `PublicRouteTable` | `AWS::EC2::RouteTable` | Associated with VPC |
| `PublicRoute` | `AWS::EC2::Route` | `0.0.0.0/0` → InternetGateway |
| `PublicSubnetARouteAssoc` | `AWS::EC2::SubnetRouteTableAssociation` | PublicSubnetA ↔ PublicRouteTable |
| `PublicSubnetCRouteAssoc` | `AWS::EC2::SubnetRouteTableAssociation` | PublicSubnetC ↔ PublicRouteTable |
| `PrivateRouteTable` | `AWS::EC2::RouteTable` | Associated with VPC; no internet route (isolated) |
| `PrivateSubnetARouteAssoc` | `AWS::EC2::SubnetRouteTableAssociation` | PrivateSubnetA ↔ PrivateRouteTable |
| `PrivateSubnetCRouteAssoc` | `AWS::EC2::SubnetRouteTableAssociation` | PrivateSubnetC ↔ PrivateRouteTable |

#### Compute Layer

| Logical ID | Type | Key Properties |
| ---------- | ---- | -------------- |
| `EC2SecurityGroup` | `AWS::EC2::SecurityGroup` | No inbound rules; no outbound restrictions |
| `EC2Instance` | `AWS::EC2::Instance` | InstanceType: !Ref InstanceType, SubnetId: PrivateSubnetA, ImageId: SSM dynamic ref, SecurityGroupIds: [EC2SecurityGroup] |

**Total resource count**: 14 resources

> **Note**: NAT Gateway and IAM Instance Profile are intentionally omitted. This is a
> CI/CD verification project — the EC2 instance's existence in the private subnet is
> sufficient to prove the pipeline works. Internet access from private subnets is not
> required for the verification goal.

### Outputs

| Output Key | Value | Description |
| ---------- | ----- | ----------- |
| `VPCId` | `!Ref VPC` | VPC identifier |
| `PublicSubnetAId` | `!Ref PublicSubnetA` | Public subnet in AZ-a |
| `PublicSubnetCId` | `!Ref PublicSubnetC` | Public subnet in AZ-c |
| `PrivateSubnetAId` | `!Ref PrivateSubnetA` | Private subnet in AZ-a (EC2 lives here) |
| `PrivateSubnetCId` | `!Ref PrivateSubnetC` | Private subnet in AZ-c |
| `EC2InstanceId` | `!Ref EC2Instance` | EC2 instance in private subnet |

---

## Pipeline State Machine

Each pipeline run progresses through these states. Both platforms implement the same
logical flow; the YAML syntax differs.

```
PUSH TO MAIN
     │
     ▼
[1] LINT (cfn-lint)
     │ fail → pipeline FAILED (no AWS calls made)
     ▼
[2] VALIDATE (aws cloudformation validate-template)
     │ fail → pipeline FAILED (no stack changes)
     ▼
[3] DETECT STACK (describe-stacks)
     │ → CHANGESET_TYPE = CREATE | UPDATE
     │ → WAIT_COMMAND = stack-create-complete | stack-update-complete
     ▼
[4] CREATE CHANGE SET (create-change-set --change-set-type $CHANGESET_TYPE)
     │
     ▼
[5] POLL CHANGE SET STATUS
     │ Status=FAILED, reason="didn't contain changes"
     │   → delete change set → pipeline SUCCESS (no-op)
     │ Status=FAILED, other reason → pipeline FAILED
     │ Status=CREATE_COMPLETE → continue
     ▼
[6] DISPLAY CHANGE SET (describe-change-set → table in log)
     │
     ▼
[7] EXECUTE CHANGE SET (execute-change-set)
     │
     ▼
[8] WAIT FOR STACK ($WAIT_COMMAND)
     │ success → pipeline SUCCESS
     │ fail → describe-stack-events (FAILED events only) → pipeline FAILED
```

---

## Repository File Layout

```
cfn-practice/
├── cfn/
│   └── template.yaml                    # CloudFormation template (single source of truth)
├── scripts/
│   └── pipeline/
│       └── deploy.sh                    # Shared deploy logic (AWS CLI); called by both pipelines
├── .github/
│   └── workflows/
│       └── deploy.yml                   # GitHub Actions pipeline definition
├── .azure/
│   └── pipelines/
│       └── deploy.yml                   # Azure Pipelines definition
├── .cfnlintrc.yaml                      # cfn-lint configuration
└── specs/
    └── 001-cfn-cicd-compare/            # This feature's design artifacts
        ├── plan.md
        ├── research.md
        ├── data-model.md
        ├── quickstart.md
        └── contracts/
```

---

## Stack Identity Model

Two stacks are deployed from the same template, managed by separate pipelines:

| Stack Name | Managed By | AWS Region | Change Set Prefix |
| ---------- | ---------- | ---------- | ----------------- |
| `cfn-practice-gha` | GitHub Actions | `ap-northeast-1` | `gha-deploy-` |
| `cfn-practice-azdo` | Azure Pipelines | `ap-northeast-1` | `azdo-deploy-` |

Both stacks are identical in infrastructure. Separate names prevent concurrent
CloudFormation update conflicts.
