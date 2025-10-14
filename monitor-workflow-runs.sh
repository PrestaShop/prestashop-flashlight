#!/bin/sh
set -eu

usage() {
  echo "Usage:"
  echo "  $0 --workflow <workflow.yml> --run-ids \"<id1> <id2> ...\" [--cancel] [--delay-between-checks <minutes>]"
  echo "  $0 --workflow <workflow.yml> --since \"2025-09-01T00:00:00Z\" [--cancel] [--delay-between-checks <minutes>]"
  exit 1
}

RUN_IDS=""
SINCE=""
CANCEL=false
WORKFLOW=""
REPO="prestashop/prestashop-flashlight"
DELAY_BETWEEN_CHECKS_IN_MIN=30

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --workflow)
      shift
      WORKFLOW="$1"
      ;;
    --run-ids)
      shift
      RUN_IDS="$1"
      ;;
    --since)
      shift
      SINCE="$1"
      ;;
    --cancel)
      shift
      CANCEL=true
      ;;
    --delay-between-checks)
      shift
      DELAY_BETWEEN_CHECKS_IN_MIN="$1"
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if [ -z "$WORKFLOW" ]; then
  echo "❌ Missing required argument: --workflow"
  usage
fi

if [ -z "$RUN_IDS" ] && [ -z "$SINCE" ]; then
  usage
fi

if [ -n "$SINCE" ]; then
  echo "Fetching all runs for workflow $WORKFLOW since $SINCE..."
  RUN_IDS=$(gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --limit 1000 \
    --json databaseId,createdAt \
    -q ".[] | select(.createdAt >= \"$SINCE\") | .databaseId")
fi

if [ -z "$RUN_IDS" ]; then
  echo "No runs to monitor or rerun."
  exit 0
fi

# Monitoring loop
echo "Monitoring workflow runs..."
while :; do
  ALL_DONE=true
  for RUN_ID in $RUN_IDS; do
    STATUS=$(gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion -q '.status' 2> /dev/null || echo "not_found")
    CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json status,conclusion -q '.conclusion' 2> /dev/null || echo "unknown")

    if [ "$STATUS" = "not_found" ]; then
      echo "Run $RUN_ID not found (it may have been deleted)."
      continue
    elif [ "$STATUS" = "unknown" ]; then
      echo "Could not fetch status for run $RUN_ID (possible GitHub API error)."
      ALL_DONE=false
      continue
    fi

    if [ "$STATUS" != "completed" ]; then
      if [ "$CANCEL" = true ]; then
        echo "Run $RUN_ID is in progress, cancelling..."
        if ! gh run cancel "$RUN_ID" --repo "$REPO"; then
          echo "⚠️  Warning: cancel attempt for $RUN_ID failed."
        fi
      else
        echo "Run $RUN_ID still in progress..."
      fi
      ALL_DONE=false
    elif [ "$CONCLUSION" = "failure" ] && [ "$CANCEL" = false ]; then
      echo "Run $RUN_ID failed, attempting to rerun only failed jobs..."
      if ! gh run rerun "$RUN_ID" --repo "$REPO" --failed; then
        echo "⚠️  Warning: rerun attempt for $RUN_ID failed (possibly a GitHub 500 error)."
        # Will retry on next loop
      fi
      ALL_DONE=false
    else
      echo "Run $RUN_ID succeeded."
    fi
  done

  if [ "$ALL_DONE" = true ]; then
    echo "✅ All workflow runs completed successfully!"
    break
  fi

  if [ "$CANCEL" = true ]; then
    echo "All runs that had to be cancelled have been cancelled."
    break
  fi

  echo "Waiting $DELAY_BETWEEN_CHECKS_IN_MIN minutes before next check..."
  sleep $((DELAY_BETWEEN_CHECKS_IN_MIN * 60))
done