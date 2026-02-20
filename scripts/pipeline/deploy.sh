#!/usr/bin/env bash
# deploy.sh — Shared CloudFormation deploy logic for GitHub Actions and Azure Pipelines.
#
# Required environment variables:
#   STACK_NAME       — CloudFormation stack name (e.g. cfn-practice-gha)
#   TEMPLATE_FILE    — Path to the CloudFormation template (e.g. cfn/template.yaml)
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION — AWS credentials
#
# Exit codes:
#   0 — Success (deployed, or no changes detected)
#   1 — Failure (lint error, validation error, changeset error, stack update failed)

set -euo pipefail

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

if [[ -z "${STACK_NAME:-}" ]]; then
  echo "ERROR: STACK_NAME is not set" >&2
  exit 1
fi

if [[ -z "${TEMPLATE_FILE:-}" ]]; then
  echo "ERROR: TEMPLATE_FILE is not set" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "ERROR: Template file not found: $TEMPLATE_FILE" >&2
  exit 1
fi

echo "=================================================================="
echo "  Stack:    $STACK_NAME"
echo "  Template: $TEMPLATE_FILE"
echo "  Region:   ${AWS_REGION:-<not set>}"
echo "=================================================================="

# ---------------------------------------------------------------------------
# Step 1: cfn-lint
# ---------------------------------------------------------------------------

echo ""
echo "── Step 1/7: cfn-lint ──────────────────────────────────────────────"
cfn-lint "$TEMPLATE_FILE"
echo "cfn-lint passed."

# ---------------------------------------------------------------------------
# Step 2: aws cloudformation validate-template
# ---------------------------------------------------------------------------

echo ""
echo "── Step 2/7: Validate template ─────────────────────────────────────"
aws cloudformation validate-template \
  --template-body "file://${TEMPLATE_FILE}" \
  --output text \
  --query 'Description' 2>&1
echo "Template validation passed."

# ---------------------------------------------------------------------------
# Step 3: Detect stack state (CREATE vs UPDATE, check ROLLBACK_COMPLETE)
# ---------------------------------------------------------------------------

echo ""
echo "── Step 3/7: Detect stack state ────────────────────────────────────"

STACK_STATUS=""
if aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null > /tmp/stack_status.txt; then
  STACK_STATUS=$(cat /tmp/stack_status.txt)
fi

if [[ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]]; then
  echo ""
  echo "ERROR: Stack '$STACK_NAME' is in ROLLBACK_COMPLETE state." >&2
  echo "       The stack must be manually deleted before redeployment." >&2
  echo ""
  echo "  Run the following command to delete the stack:"
  echo "    aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  echo ""
  exit 1
fi

if [[ -z "$STACK_STATUS" ]]; then
  CHANGESET_TYPE="CREATE"
  WAIT_COMMAND="stack-create-complete"
  echo "Stack does not exist — will CREATE."
else
  CHANGESET_TYPE="UPDATE"
  WAIT_COMMAND="stack-update-complete"
  echo "Stack exists (status: $STACK_STATUS) — will UPDATE."
fi

# ---------------------------------------------------------------------------
# Step 4: Create Change Set
# ---------------------------------------------------------------------------

echo ""
echo "── Step 4/7: Create Change Set ─────────────────────────────────────"

CHANGESET_NAME="${STACK_NAME}-$(date +%s)"
echo "Change Set name: $CHANGESET_NAME"

aws cloudformation create-change-set \
  --stack-name "$STACK_NAME" \
  --template-body "file://${TEMPLATE_FILE}" \
  --change-set-name "$CHANGESET_NAME" \
  --change-set-type "$CHANGESET_TYPE" \
  --output text \
  --query 'Id' 2>&1

echo "Change Set creation initiated."

# ---------------------------------------------------------------------------
# Step 5: Poll Change Set status
# ---------------------------------------------------------------------------

echo ""
echo "── Step 5/7: Wait for Change Set ───────────────────────────────────"

while true; do
  CS_STATUS=$(aws cloudformation describe-change-set \
    --stack-name "$STACK_NAME" \
    --change-set-name "$CHANGESET_NAME" \
    --query 'Status' \
    --output text)

  CS_STATUS_REASON=$(aws cloudformation describe-change-set \
    --stack-name "$STACK_NAME" \
    --change-set-name "$CHANGESET_NAME" \
    --query 'StatusReason' \
    --output text 2>/dev/null || echo "")

  echo "Change Set status: $CS_STATUS"

  if [[ "$CS_STATUS" == "CREATE_COMPLETE" ]]; then
    break
  elif [[ "$CS_STATUS" == "FAILED" ]]; then
    if echo "$CS_STATUS_REASON" | grep -q "didn't contain changes"; then
      echo ""
      echo "No changes detected — stack is up to date."
      aws cloudformation delete-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGESET_NAME"
      echo "Empty Change Set deleted."
      exit 0
    else
      echo ""
      echo "ERROR: Change Set failed: $CS_STATUS_REASON" >&2
      aws cloudformation delete-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGESET_NAME" 2>/dev/null || true
      exit 1
    fi
  fi

  sleep 5
done

# ---------------------------------------------------------------------------
# Step 6: Display Change Set contents
# ---------------------------------------------------------------------------

echo ""
echo "── Step 6/7: Change Set contents ───────────────────────────────────"
printf "%-10s | %-40s | %-30s | %-12s\n" "Action" "ResourceType" "LogicalResourceId" "Replacement"
printf "%-10s-+-%-40s-+-%-30s-+-%-12s\n" "----------" "----------------------------------------" "------------------------------" "------------"

aws cloudformation describe-change-set \
  --stack-name "$STACK_NAME" \
  --change-set-name "$CHANGESET_NAME" \
  --query 'Changes[].ResourceChange' \
  --output json \
| jq -r '.[] | [.Action, .ResourceType, .LogicalResourceId, .Replacement] | @tsv' \
| while IFS=$'\t' read -r action resource_type logical_id replacement; do
    printf "%-10s | %-40s | %-30s | %-12s\n" \
      "$action" "$resource_type" "$logical_id" "${replacement:-N/A}"
  done

# ---------------------------------------------------------------------------
# Step 7: Execute Change Set
# ---------------------------------------------------------------------------

echo ""
echo "── Step 7/7: Execute Change Set + Wait ─────────────────────────────"
aws cloudformation execute-change-set \
  --stack-name "$STACK_NAME" \
  --change-set-name "$CHANGESET_NAME"

echo "Executing Change Set. Waiting for stack ${WAIT_COMMAND}..."

if aws cloudformation wait "$WAIT_COMMAND" --stack-name "$STACK_NAME"; then
  echo ""
  FINAL_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text)
  echo "=================================================================="
  echo "  SUCCESS: Stack '$STACK_NAME' — $FINAL_STATUS"
  echo "=================================================================="
  exit 0
else
  echo ""
  echo "ERROR: Stack update failed. Fetching CloudFormation events..." >&2

  echo ""
  echo "── Failed CloudFormation Stack Events ──────────────────────────────"
  aws cloudformation describe-stack-events \
    --stack-name "$STACK_NAME" \
    --query "StackEvents[?contains('CREATE_FAILED UPDATE_FAILED DELETE_FAILED ROLLBACK_FAILED UPDATE_ROLLBACK_FAILED', ResourceStatus)].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]" \
    --output table 2>/dev/null || \
  aws cloudformation describe-stack-events \
    --stack-name "$STACK_NAME" \
    --output json \
  | jq -r '.StackEvents[]
    | select(.ResourceStatus | test("FAILED|ROLLBACK"))
    | "\(.Timestamp) [\(.LogicalResourceId)] \(.ResourceStatus): \(.ResourceStatusReason // "no reason")"' \
  | head -20

  echo ""
  FAILED_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "UNKNOWN")

  echo "Final stack status: $FAILED_STATUS"

  if [[ "$FAILED_STATUS" == "ROLLBACK_COMPLETE" ]]; then
    echo ""
    echo "Stack is in ROLLBACK_COMPLETE. Manual cleanup required:"
    echo "  aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  fi

  exit 1
fi
