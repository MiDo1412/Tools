#!/usr/bin/env bash
# ==============================================================
#  GitHub Repository Auto-Updater (Linux)
#  Checks for a newer version and downloads it if available.
#  Designed to run via systemd at boot.
# ==============================================================

# ============================================================
#  CONFIGURATION — adjust these values
# ============================================================
GITHUB_OWNER="octocat"
GITHUB_REPO="Hello-World"
GITHUB_BRANCH="main"
INSTALL_PATH="/opt/myapp"           # Local destination folder
VERSION_FILE="$INSTALL_PATH/.version"
LOG_FILE="/var/log/github-updater.log"
USE_RELEASES=false                  # true = track Releases, false = track branch commits
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"   # Personal Access Token (required for private repos)
# ============================================================

# ----- validate config ---------------------------------------
if [[ -z "${GITHUB_TOKEN:-}" || "$GITHUB_TOKEN" == ghp_xxx* ]]; then
    echo "ERROR: GITHUB_TOKEN is not set. A Personal Access Token is required for private repositories." >&2
    exit 1
fi

API_BASE="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}"
# -L follows the redirect that GitHub's API zipball/tarball endpoint returns
CURL_OPTS=(-fsSL -L --max-time 60
    -H "User-Agent: github-updater-sh"
    -H "Accept: application/vnd.github+json"
    -H "Authorization: Bearer $GITHUB_TOKEN"
)

# ----- helpers -----------------------------------------------
log() {
    local level="${2:-INFO}"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$ts] [$level] $1"
    echo "$line"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$line" >> "$LOG_FILE"
}

die() { log "$1" "ERROR"; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || die "Required command '$1' not found. Install it and retry."
}

# ----- get remote version ------------------------------------
get_remote_version() {
    if [[ "$USE_RELEASES" == true ]]; then
        local json; json=$(curl "${CURL_OPTS[@]}" "$API_BASE/releases/latest") \
            || die "Failed to fetch latest release from GitHub API."
        REMOTE_ID=$(echo "$json" | grep -m1 '"tag_name"' | sed 's/.*"tag_name": *"\(.*\)".*/\1/')
        # Use API tarball endpoint — supports Bearer auth for private repos
        REMOTE_URL="${API_BASE}/tarball/refs/tags/${REMOTE_ID}"
    else
        local json; json=$(curl "${CURL_OPTS[@]}" "$API_BASE/commits/${GITHUB_BRANCH}") \
            || die "Failed to fetch latest commit from GitHub API."
        REMOTE_ID=$(echo "$json" | grep -m1 '"sha"' | sed 's/.*"sha": *"\(.*\)".*/\1/')
        # Use API tarball endpoint — supports Bearer auth for private repos
        REMOTE_URL="${API_BASE}/tarball/${GITHUB_BRANCH}"
    fi
}

# ----- get local version -------------------------------------
get_local_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        LOCAL_ID=$(cat "$VERSION_FILE")
    else
        LOCAL_ID=""
    fi
}

# ----- download and install ----------------------------------
install_update() {
    local tmp_tar; tmp_tar=$(mktemp /tmp/gh_update_XXXXXX.tar.gz)
    local tmp_dir; tmp_dir=$(mktemp -d /tmp/gh_update_XXXXXX)

    # Cleanup on exit
    trap 'rm -rf "$tmp_tar" "$tmp_dir"' RETURN

    log "Downloading from $REMOTE_URL ..."
    curl "${CURL_OPTS[@]}" --max-time 300 -o "$tmp_tar" "$REMOTE_URL" \
        || die "Download failed."

    log "Extracting archive ..."
    tar -xzf "$tmp_tar" -C "$tmp_dir" \
        || die "Extraction failed."

    # GitHub tarballs contain a single top-level directory
    local inner_dir; inner_dir=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)
    [[ -d "$inner_dir" ]] || die "Extracted archive contains no folder."

    mkdir -p "$INSTALL_PATH"

    log "Copying files to $INSTALL_PATH ..."
    # rsync preferred for reliability; fallback to cp
    if command -v rsync &>/dev/null; then
        rsync -a --delete "$inner_dir/" "$INSTALL_PATH/"
    else
        cp -a "$inner_dir/." "$INSTALL_PATH/"
    fi

    echo -n "$REMOTE_ID" > "$VERSION_FILE"
    log "Update complete. Version: $REMOTE_ID"
}

# ----- main --------------------------------------------------
require_cmd curl
require_cmd tar

log "=== GitHub Updater started ==="

get_remote_version
get_local_version

log "Remote version : $REMOTE_ID"
log "Local  version : ${LOCAL_ID:-(none)}"

if [[ "$REMOTE_ID" != "$LOCAL_ID" ]]; then
    log "New version detected — starting download ..."
    install_update
else
    log "Already up-to-date."
fi
