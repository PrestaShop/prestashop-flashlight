#!/usr/bin/env bash
# Install a Docker Hub pull-through cache (registry mirror) on this machine.
#
# What this does:
#   - Runs a registry:2 container on localhost:5000 as a systemd service
#   - Configures /etc/docker/daemon.json to route all pulls through it
#   - Schedules a daily cron job to prune blobs older than 30 days
#
# Usage:
#   ./registry-mirror/install.sh            # install
#   ./registry-mirror/install.sh uninstall  # remove everything
#
# Requirements: docker, sudo, systemd, cron

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_DATA=/var/lib/docker-registry-mirror
SERVICE_NAME=docker-registry-mirror
SERVICE_FILE=/etc/systemd/system/${SERVICE_NAME}.service
CRON_FILE=/etc/cron.d/${SERVICE_NAME}-prune
DAEMON_JSON=/etc/docker/daemon.json
MIRROR_PORT=5000
MIRROR_URL="http://localhost:${MIRROR_PORT}"

# ── helpers ────────────────────────────────────────────────────────────────────

info()  { echo "  [+] $*"; }
warn()  { echo "  [!] $*"; }
die()   { echo "  [✗] $*" >&2; exit 1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root (use sudo)."
  fi
}

check_deps() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed or not in PATH."
  command -v systemctl >/dev/null 2>&1 || die "systemd is required."
  command -v jq >/dev/null 2>&1 || die "jq is required (apt-get install jq)."
}

# ── install ────────────────────────────────────────────────────────────────────

install() {
  info "Installing Docker registry mirror..."

  # 1. Pull the registry image up-front so the service starts cleanly
  info "Pulling registry:2 image..."
  docker pull registry:2

  # 2. Create data directory
  mkdir -p "$REGISTRY_DATA"

  # 3. Install config and prune script
  mkdir -p /etc/docker-registry-mirror
  cp "${SCRIPT_DIR}/config.yml"    /etc/docker-registry-mirror/config.yml
  cp "${SCRIPT_DIR}/prune-cache.sh" /etc/docker-registry-mirror/prune-cache.sh
  chmod +x /etc/docker-registry-mirror/prune-cache.sh

  # 4. Write the systemd unit (references /etc/docker-registry-mirror, not the repo)
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Docker Registry Mirror (pull-through cache for Docker Hub)
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5s
ExecStartPre=-/usr/bin/docker stop ${SERVICE_NAME}
ExecStartPre=-/usr/bin/docker rm   ${SERVICE_NAME}
ExecStart=/usr/bin/docker run --rm \\
  --name ${SERVICE_NAME} \\
  -p 127.0.0.1:${MIRROR_PORT}:5000 \\
  -v ${REGISTRY_DATA}:/var/lib/registry \\
  -v /etc/docker-registry-mirror/config.yml:/etc/docker/registry/config.yml:ro \\
  registry:2
ExecStop=/usr/bin/docker stop ${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

  # 5. Enable and start the service
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl start  "$SERVICE_NAME"

  # Wait briefly and verify
  local retries=10
  while ! curl -sf "${MIRROR_URL}/v2/" >/dev/null 2>&1; do
    retries=$((retries - 1))
    [[ $retries -eq 0 ]] && die "Mirror did not start in time. Check: journalctl -u ${SERVICE_NAME}"
    sleep 1
  done
  info "Mirror is up at ${MIRROR_URL}"

  # 6. Configure Docker daemon to use the mirror
  configure_daemon

  # 7. Restart Docker so the mirror config takes effect
  info "Restarting Docker daemon..."
  systemctl restart docker

  # 8. Install daily prune cron
  echo "0 3 * * * root /etc/docker-registry-mirror/prune-cache.sh >> /var/log/docker-registry-prune.log 2>&1" \
    > "$CRON_FILE"
  info "Daily prune cron installed at ${CRON_FILE} (runs 03:00 every day)"

  echo ""
  info "Done. All docker pull / FROM calls will now be cached locally for 30 days."
}

configure_daemon() {
  if [[ -f "$DAEMON_JSON" ]]; then
    # Merge: add/replace registry-mirrors key, preserve the rest
    local tmp
    tmp=$(mktemp)
    jq --arg mirror "$MIRROR_URL" \
      '. + {"registry-mirrors": [$mirror]}' \
      "$DAEMON_JSON" > "$tmp"
    mv "$tmp" "$DAEMON_JSON"
    info "Updated existing ${DAEMON_JSON}"
  else
    cat > "$DAEMON_JSON" <<EOF
{
  "registry-mirrors": ["${MIRROR_URL}"]
}
EOF
    info "Created ${DAEMON_JSON}"
  fi
}

# ── uninstall ──────────────────────────────────────────────────────────────────

uninstall() {
  info "Uninstalling Docker registry mirror..."

  # Stop and disable the service
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME"
  fi
  if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
  fi
  [[ -f "$SERVICE_FILE" ]] && rm -f "$SERVICE_FILE"
  systemctl daemon-reload

  # Remove mirror from daemon.json
  if [[ -f "$DAEMON_JSON" ]]; then
    local tmp
    tmp=$(mktemp)
    jq 'del(."registry-mirrors")' "$DAEMON_JSON" > "$tmp"
    # If the file is now just "{}", remove it entirely
    if [[ "$(cat "$tmp")" == "{}" ]]; then
      rm -f "$DAEMON_JSON"
      info "Removed ${DAEMON_JSON} (was empty after cleanup)"
    else
      mv "$tmp" "$DAEMON_JSON"
      info "Removed registry-mirrors entry from ${DAEMON_JSON}"
    fi
    systemctl restart docker
  fi

  # Remove cron
  [[ -f "$CRON_FILE" ]] && rm -f "$CRON_FILE" && info "Removed cron job"

  # Remove installed config files
  rm -rf /etc/docker-registry-mirror
  info "Removed /etc/docker-registry-mirror"

  warn "Registry data at ${REGISTRY_DATA} was NOT deleted (may be large)."
  warn "To free disk space: sudo rm -rf ${REGISTRY_DATA}"

  info "Done."
}

# ── main ───────────────────────────────────────────────────────────────────────

require_root
check_deps

case "${1:-install}" in
  install)   install ;;
  uninstall) uninstall ;;
  *) die "Unknown command '${1}'. Use: install | uninstall" ;;
esac
