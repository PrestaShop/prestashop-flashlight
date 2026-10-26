#!/bin/sh
set -eu

usage() {
  echo "Usage:"
  echo "  $0 --workflow <workflow.yml> --run-ids \"<id1> <id2> ...\" [--cancel|--revive-expired] [--delay-between-checks <minutes>] [--max-queued <n>]"
  echo "  $0 --workflow <workflow.yml> --since \"2025-09-01T00:00:00Z\" [--cancel|--revive-expired] [--delay-between-checks <minutes>] [--max-queued <n>]"
  echo ""
  echo "  --max-queued <n>  Do not rerun anything while <n> runs of the workflow are queued or in progress (default: 50),"
  echo "                    so that reruns do not expire again while awaiting a runner"
  exit 1
}

RUN_IDS=""
SINCE=""
CANCEL=false
REVIVE_EXPIRED=false
WORKFLOW=""
REPO="prestashop/prestashop-flashlight"
DELAY_BETWEEN_CHECKS_IN_MIN=30
EXPIRED_RUNNER_ERROR="The job has exceeded the maximum execution time while awaiting a runner"
EXPIRED_EXECUTION_ERROR="The job has exceeded the maximum execution time"
MAX_EXECUTION_TIMEOUT_REVIVES=3
MAX_FAILURE_RERUNS=2
MAX_QUEUED=50

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
      CANCEL=true
      ;;
    --revive-expired)
      REVIVE_EXPIRED=true
      ;;
    --delay-between-checks)
      shift
      DELAY_BETWEEN_CHECKS_IN_MIN="$1"
      ;;
    --max-queued)
      shift
      MAX_QUEUED="$1"
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

if [ -n "$RUN_IDS" ] && [ -n "$SINCE" ]; then
  echo "❌ --run-ids and --since cannot be provided together"
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

# Number of times a failed run was rerun (this script's lifetime)
get_failure_reruns() {
  eval "echo \"\${FAILURE_RERUNS_$1:-0}\""
}

# Number of runs of the workflow waiting for or holding a runner
count_active_runs() {
  ACTIVE_COUNT=0
  for ACTIVE_STATUS in queued in_progress waiting pending requested; do
    COUNT=$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?status=$ACTIVE_STATUS&per_page=1" -q '.total_count' 2> /dev/null) || return 1
    ACTIVE_COUNT=$((ACTIVE_COUNT + COUNT))
  done
  echo "$ACTIVE_COUNT"
}

# rerun <run_id> [--failed]
# Reruns are throttled by MAX_QUEUED, a skipped rerun is retried on the next loop
rerun() {
  if [ "$ACTIVE" -ge "$MAX_QUEUED" ]; then
    echo "⏳ $ACTIVE runs are queued or in progress, postponing rerun of $1."
    return 1
  fi
  if gh run rerun "$@" --repo "$REPO"; then
    ACTIVE=$((ACTIVE + 1))
    return 0
  fi
  echo "⚠️  Warning: rerun attempt for $1 failed (possibly a GitHub 500 error)."
  return 1
}

# Monitoring loop
echo "Monitoring workflow runs..."
while :; do
  ALL_DONE=true
  # Unknown while the API is unreachable (e.g. rate limited): no rerun this loop
  ACTIVE=$(count_active_runs) || ACTIVE="$MAX_QUEUED"
  for RUN_ID in $RUN_IDS; do
    # A single API call per run, so that large releases stay under the API rate limit
    if RUN_STATE=$(gh api "repos/$REPO/actions/runs/$RUN_ID" -q '.status + " " + (.conclusion // "")' 2>&1); then
      STATUS="${RUN_STATE%% *}"
      CONCLUSION="${RUN_STATE#* }"
    elif echo "$RUN_STATE" | grep -qF "HTTP 404"; then
      STATUS="not_found"
    else
      STATUS="unknown"
    fi

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
      RERUNS=$(get_failure_reruns "$RUN_ID")
      if [ "$RERUNS" -ge "$MAX_FAILURE_RERUNS" ]; then
        echo "❌ Run $RUN_ID failed, already rerun $RERUNS times, giving up."
      else
        echo "Run $RUN_ID failed, attempting to rerun only failed jobs (rerun $((RERUNS + 1))/$MAX_FAILURE_RERUNS)..."
        if rerun "$RUN_ID" --failed; then
          eval "FAILURE_RERUNS_$RUN_ID=$((RERUNS + 1))"
        fi
        ALL_DONE=false
      fi
    elif [ "$CONCLUSION" = "cancelled" ] && [ "$REVIVE_EXPIRED" = true ]; then
      if has_job_annotation "$RUN_ID" "$EXPIRED_RUNNER_ERROR"; then
        echo "Run $RUN_ID was cancelled due to runner timeout, reviving..."
        rerun "$RUN_ID" || true # Will retry on next loop
        ALL_DONE=false
      elif has_job_annotation "$RUN_ID" "$EXPIRED_EXECUTION_ERROR"; then
        REVIVES=$(get_execution_timeout_revives "$RUN_ID")
        if [ "$REVIVES" -ge "$MAX_EXECUTION_TIMEOUT_REVIVES" ]; then
          echo "Run $RUN_ID exceeded the maximum execution time, already revived $REVIVES times, giving up."
        else
          echo "Run $RUN_ID exceeded the maximum execution time, reviving (revive $((REVIVES + 1))/$MAX_EXECUTION_TIMEOUT_REVIVES)..."
          if rerun "$RUN_ID"; then
            eval "EXECUTION_TIMEOUT_REVIVES_$RUN_ID=$((REVIVES + 1))"
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
    echo "✅ All workflow runs completed."
    break
  fi

  if [ "$CANCEL" = true ]; then
    echo "All runs that had to be cancelled have been cancelled."
    break
  fi

  echo "Waiting $DELAY_BETWEEN_CHECKS_IN_MIN minutes before next check..."
  sleep $((DELAY_BETWEEN_CHECKS_IN_MIN * 60))
done