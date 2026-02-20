# Feature Specification: CloudFormation CI/CD Platform Comparison

**Feature Branch**: `001-cfn-cicd-compare`
**Created**: 2026-02-21
**Status**: Draft
**Input**: User description: "CloudFormation IaC CI/CD comparison between Azure DevOps and GitHub Actions"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automated Deployment via GitHub Actions (Priority: P1)

An IaC engineer pushes a CloudFormation template change to the GitHub repository. The
GitHub Actions pipeline automatically validates the template, creates a Change Set showing
what will change in AWS, and deploys the stack. The engineer can see the full deployment
outcome in the pipeline run log without touching the AWS Console.

**Why this priority**: This is the foundational MVP. Proving that a CloudFormation stack
can be deployed end-to-end from a code push — with visibility and safety — is the core
value. GitHub Actions is the first platform because it removes Azure DevOps organization
setup from the critical path.

**Independent Test**: Push a CloudFormation template change to the GitHub repository main
branch. Confirm the pipeline triggers, the Change Set contents appear in the log, the
AWS stack updates, and the pipeline reports success — without any manual Console access.

**Acceptance Scenarios**:

1. **Given** a valid CloudFormation template change is pushed to the main branch,
   **When** the GitHub Actions pipeline triggers, **Then** the pipeline completes
   successfully and the AWS CloudFormation stack reflects the change within 15 minutes.
2. **Given** the pipeline has run a deployment, **When** the engineer inspects the
   pipeline logs, **Then** the Change Set details (resource additions, modifications,
   and deletions) are visible in the log output before the deploy step executes.
3. **Given** a syntactically invalid CloudFormation template is pushed, **When** the
   pipeline runs the validation step, **Then** the pipeline fails early with a clear
   error message and no stack changes are applied.

---

### User Story 2 - Pre-Deploy Change Visibility (Priority: P2)

Before any infrastructure change is applied, the engineer automatically sees exactly
which AWS resources will be created, modified, or deleted — surfaced in the pipeline
output without any manual steps.

**Why this priority**: Change visibility is the safety mechanism that makes automated
deployment suitable for real-world use. Without it, an automated pipeline is a risky
black box. This story must be solid before replicating to a second platform.

**Independent Test**: Modify a CloudFormation resource property that causes resource
replacement (e.g., change an EC2 instance type or subnet assignment). Confirm that the
Change Set in the pipeline log shows the replacement action — including the resource
logical ID and replacement flag — before any changes are applied to AWS.

**Acceptance Scenarios**:

1. **Given** a CloudFormation change that modifies an existing resource, **When** the
   pipeline runs, **Then** the Change Set lists the affected resource with its action
   (Add / Modify / Remove) and replacement flag before the deployment step begins.
2. **Given** a CloudFormation change that would delete a resource, **When** the pipeline
   runs, **Then** the Change Set clearly indicates the deletion before the deploy step
   proceeds.
3. **Given** a CloudFormation push with no actual resource impact (e.g., only metadata
   or description change), **When** the pipeline runs, **Then** the pipeline detects an
   empty Change Set and exits successfully without attempting a deployment.

---

### User Story 3 - Failure Investigation and Recovery (Priority: P3)

When a CloudFormation deployment fails, the engineer can determine the root cause from
pipeline logs alone and can confirm automatic rollback to the previous known-good state
— without requiring AWS Console access.

**Why this priority**: Without reliable failure recovery, a single bad deployment can
permanently block the stack from future changes. This story makes the CI/CD loop
complete and safe for ongoing experimentation.

**Independent Test**: Push a deliberately broken CloudFormation configuration that passes
template validation but fails during stack update (e.g., an EC2 instance type not
available in the target AZ). Verify the failure reason appears in the pipeline log, the
stack rolls back automatically, and a subsequent corrected push deploys successfully.

**Acceptance Scenarios**:

1. **Given** a deployment fails during a stack update, **When** the engineer reviews the
   pipeline log, **Then** the CloudFormation stack event failure reason is visible in the
   log output without opening the AWS Console.
2. **Given** a failed deployment, **When** CloudFormation's automatic rollback completes,
   **Then** the pipeline reports rollback complete and identifies the stack as restored
   to its prior state.
3. **Given** a corrected template pushed after a failure, **When** the pipeline re-runs,
   **Then** the deployment completes successfully without requiring manual stack cleanup.

---

### User Story 4 - Azure DevOps Pipeline Parity (Priority: P4)

The same CloudFormation template and deployment workflow is reproduced on Azure DevOps.
The engineer can push a change to the Azure DevOps repository and observe the same
end-to-end behavior — validate → change-set preview → deploy — with structured
observations of where the experience differs from GitHub Actions.

**Why this priority**: This is the comparison objective. After both pipelines are
working, the engineer has concrete, first-hand evidence to compare platform ergonomics,
configuration syntax, secrets management, and operational visibility side-by-side.

**Independent Test**: Push the same CloudFormation template change to the Azure DevOps
repository. Confirm the Azure Pipelines workflow completes and the AWS stack is updated,
mirroring the GitHub Actions outcome. Record at least 3 concrete differences observed
between the two pipeline runs.

**Acceptance Scenarios**:

1. **Given** a CloudFormation template change is pushed to the Azure DevOps repository,
   **When** the Azure Pipelines workflow triggers, **Then** the pipeline completes and
   the AWS stack is updated, mirroring the GitHub Actions outcome.
2. **Given** both pipelines have been run with the same template change, **When** the
   engineer compares the run summaries, **Then** the following comparison points are
   observable from pipeline artifacts alone: authentication setup, secrets handling,
   YAML syntax differences, job structure, and deployment log quality.
3. **Given** a deployment failure on the Azure DevOps pipeline, **When** the engineer
   applies the recovery procedure used on GitHub Actions, **Then** recovery succeeds
   using Azure DevOps–native steps.

---

### Edge Cases

- What happens when the CloudFormation stack enters `ROLLBACK_COMPLETE` state (requires
  manual deletion before a new deployment can proceed)?
- How does the pipeline behave if AWS credentials expire mid-run?
- What happens if both pipelines are triggered simultaneously and attempt to update the
  same stack concurrently?
- What happens when the Change Set is empty — does the pipeline succeed gracefully or
  treat it as an error?
- How is an incompletely-created stack cleaned up when the very first deployment fails?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Both pipelines MUST trigger automatically when a change is pushed to the
  designated branch of their respective repository.
- **FR-002**: Each pipeline MUST validate the CloudFormation template before attempting
  to create a Change Set or deploy.
- **FR-003**: Each pipeline MUST create a CloudFormation Change Set and output its
  contents (resource logical ID, action, replacement flag) in the pipeline log before
  applying any changes.
- **FR-004**: Each pipeline MUST deploy the CloudFormation stack and report pipeline
  success or failure as its final status.
- **FR-005**: When a deployment fails, the pipeline MUST surface the CloudFormation stack
  event failure reason in the pipeline log.
- **FR-006**: CloudFormation MUST be configured to roll back automatically to the
  previous stack state on deployment failure.
- **FR-007**: AWS credentials MUST be stored as pipeline secrets — never embedded in
  template files or pipeline YAML.
- **FR-008**: The CloudFormation template MUST define a VPC with public and private
  subnets spanning at least 2 Availability Zones, with one or more EC2 instances in the
  private subnets.
- **FR-009**: When a Change Set contains no changes, the pipeline MUST exit successfully
  without attempting a deployment.
- **FR-010**: Both pipeline definition files MUST reside in the same repository so the
  CloudFormation template is the single source of truth for both platforms.

### Key Entities

- **CloudFormation Template**: The IaC artifact defining the AWS infrastructure (VPC,
  subnets, EC2). Shared single source of truth for both pipelines.
- **CloudFormation Stack**: The deployed AWS resource group managed by the template.
  Two stacks exist — one per platform — to avoid concurrent-update conflicts.
- **CloudFormation Change Set**: A preview artifact generated before deployment, listing
  resource-level changes (action, resource type, logical ID, replacement flag).
- **GitHub Actions Workflow**: Pipeline definition that runs on GitHub compute on push,
  orchestrating validate → change-set → deploy steps.
- **Azure Pipelines Definition**: Equivalent pipeline definition for Azure DevOps,
  producing the same deployment outcome via Azure's compute infrastructure.
- **Pipeline Secrets**: AWS credentials stored in each platform's secure variable store;
  never committed to the repository.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A CloudFormation template change pushed to either repository reaches a
  deployed AWS stack state within 15 minutes of the push, with zero manual steps
  required after the push.
- **SC-002**: For every pipeline run that applies a change, the Change Set contents
  (resource logical ID, action, replacement flag) are visible in the pipeline log before
  the deploy step begins.
- **SC-003**: When a deployment fails, the engineer can identify the failure reason from
  pipeline logs alone — without opening the AWS Console — in under 5 minutes, and the
  stack is automatically restored to its prior state.
- **SC-004**: After running both pipelines with the same template change, the engineer
  can produce a written comparison covering at least 5 concrete differences (setup,
  syntax, secrets handling, log quality, recovery behavior) between GitHub Actions and
  Azure DevOps.
- **SC-005**: The repository contains all configuration needed to deploy a fresh
  CloudFormation stack from either platform with no manual infrastructure pre-steps
  beyond one-time credentials setup in each platform's secret store.

## Assumptions

- An AWS account is available with permissions to create VPC, subnets, EC2, and related
  networking resources.
- Both a GitHub account (for GitHub Actions) and an Azure DevOps organization (for
  Azure Pipelines) already exist.
- This is a personal, non-production environment; manual approval gates before deployment
  are not required.
- CloudFormation's built-in automatic rollback on failure is sufficient; no separate
  pipeline-level rollback step is needed.
- The two pipelines deploy to separate CloudFormation stacks (e.g., `cfn-practice-gha`
  and `cfn-practice-azdo`) within the same AWS account to avoid concurrent-update
  conflicts.
- No NAT Gateway is included. The EC2 instance in the private subnet has no outbound
  internet access, which is sufficient for the CI/CD verification goal (we only need
  the instance to exist; we do not need to connect to it).
