#!/bin/sh
set -eu

usage() {
  echo "Usage:"
  echo "  $0 --workflow <workflow.yml> --run-ids \"<id1> <id2> ...\" [--cancel|--revive-expired] [--delay-between-checks <minutes>]"
  echo "  $0 --workflow <workflow.yml> --run-ids-file <file> [--cancel|--revive-expired] [--delay-between-checks <minutes>]"
  echo "  $0 --workflow <workflow.yml> --since \"2025-09-01T00:00:00Z\" [--cancel|--revive-expired] [--delay-between-checks <minutes>]"
  exit 1
}

RUN_IDS=""
RUN_IDS_FILE=""
SINCE=""
CANCEL=false
REVIVE_EXPIRED=false
WORKFLOW=""
REPO="prestashop/prestashop-flashlight"
DELAY_BETWEEN_CHECKS_IN_MIN=30
EXPIRED_RUNNER_ERROR="The job has exceeded the maximum execution time while awaiting a runner"
EXPIRED_EXECUTION_ERROR="The job has exceeded the maximum execution time"
MAX_EXECUTION_TIMEOUT_REVIVES=3

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
    --run-ids-file)
      shift
      RUN_IDS_FILE="$1"
      ;;
    --since)
      shift
      SINCE="$1"
      ;;
    --cancel)
      CANCEL=true
      ;;
    --revive-expired)
      REVIVE_EXPIRED=true
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

if [ -n "$RUN_IDS_FILE" ]; then
  if [ -n "$RUN_IDS" ]; then
    echo "❌ --run-ids and --run-ids-file cannot be provided together"
    usage
  fi
  if [ ! -r "$RUN_IDS_FILE" ]; then
    echo "❌ Cannot read run IDs file: $RUN_IDS_FILE"
    exit 1
  fi
  RUN_IDS=$(cat "$RUN_IDS_FILE")
  if [ -z "$RUN_IDS" ]; then
    echo "❌ Run IDs file is empty: $RUN_IDS_FILE"
    exit 1
  fi
fi

if [ -z "$RUN_IDS" ] && [ -z "$SINCE" ]; then
  usage
fi

if [ -n "$RUN_IDS" ] && [ -n "$SINCE" ]; then
  echo "❌ --run-ids/--run-ids-file and --since cannot be provided together"
  usage
fi

if [ "$CANCEL" = true ] && [ "$REVIVE_EXPIRED" = true ]; then
  echo "❌ --cancel and --revive-expired cannot be provided together"
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

is_expired_runner_timeout() {
  gh run view "$1" --repo "$REPO" --log 2> /dev/null | grep -qF "$EXPIRED_RUNNER_ERROR"
}

# The "maximum execution time" message is reported as a job annotation, not in the logs
has_job_annotation() {
  for JOB_ID in $(gh run view "$1" --repo "$REPO" --json jobs -q '.jobs[].databaseId' 2> /dev/null); do
    if gh api "repos/$REPO/check-runs/$JOB_ID/annotations" -q '.[].message' 2> /dev/null | grep -qF "$2"; then
      return 0
    fi
  done
  return 1
}

# Number of times a run was revived for exceeding the maximum execution time (this script's lifetime)
get_execution_timeout_revives() {
  eval "echo \"\${EXECUTION_TIMEOUT_REVIVES_$1:-0}\""
}

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
    elif [ "$CONCLUSION" = "cancelled" ] && [ "$REVIVE_EXPIRED" = true ]; then
      if is_expired_runner_timeout "$RUN_ID" || has_job_annotation "$RUN_ID" "$EXPIRED_RUNNER_ERROR"; then
        echo "Run $RUN_ID was cancelled due to runner timeout, reviving..."
        if ! gh run rerun "$RUN_ID" --repo "$REPO"; then
          echo "⚠️  Warning: revive attempt for $RUN_ID failed (possibly a GitHub 500 error)."
          # Will retry on next loop
        fi
        ALL_DONE=false
      elif has_job_annotation "$RUN_ID" "$EXPIRED_EXECUTION_ERROR"; then
        REVIVES=$(get_execution_timeout_revives "$RUN_ID")
        if [ "$REVIVES" -ge "$MAX_EXECUTION_TIMEOUT_REVIVES" ]; then
          echo "Run $RUN_ID exceeded the maximum execution time, already revived $REVIVES times, giving up."
        else
          echo "Run $RUN_ID exceeded the maximum execution time, reviving (revive $((REVIVES + 1))/$MAX_EXECUTION_TIMEOUT_REVIVES)..."
          if gh run rerun "$RUN_ID" --repo "$REPO"; then
            eval "EXECUTION_TIMEOUT_REVIVES_$RUN_ID=$((REVIVES + 1))"
          else
            echo "⚠️  Warning: revive attempt for $RUN_ID failed (possibly a GitHub 500 error)."
            # Will retry on next loop
          fi
          ALL_DONE=false
        fi
      else
        echo "Run $RUN_ID was cancelled (not a timeout), leaving as is."
      fi
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