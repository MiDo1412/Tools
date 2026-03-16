<#
.SYNOPSIS
    GitHub Repository Auto-Updater (Windows)
.DESCRIPTION
    Checks a GitHub repository for a newer version and downloads it if available.
    Designed to run at system startup via Task Scheduler.
#>

# ============================================================
#  CONFIGURATION - adjust these values
# ============================================================
$GITHUB_OWNER  = "MiDo1412"                          # GitHub username or org
$GITHUB_REPO   = "AutoDartsCaller"                      # Repository name
$GITHUB_BRANCH = "main"                             # Branch to track
$INSTALL_PATH  = "C:\Tools\caller"                   # Local destination folder
$VERSION_FILE  = "$INSTALL_PATH\.version"           # Stores the last known commit SHA
$LOG_FILE      = "$INSTALL_PATH\updater.log"        # Log file path
$USE_RELEASES  = $false                             # true = track Releases, false = track branch commits
$GITHUB_TOKEN  = ""         # Personal Access Token (required for private repos)
# ============================================================

$ErrorActionPreference = "Stop"
$API_BASE = "https://api.github.com/repos/$GITHUB_OWNER/$GITHUB_REPO"

# ----- validate config ---------------------------------------
if (-not $GITHUB_TOKEN -or $GITHUB_TOKEN -like "ghp_xxx*") {
    Write-Error "GITHUB_TOKEN is not set. A Personal Access Token is required for private repositories."
    exit 1
}

# ----- helpers -----------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    if (-not (Test-Path (Split-Path $LOG_FILE))) {
        New-Item -ItemType Directory -Path (Split-Path $LOG_FILE) -Force | Out-Null
    }
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Get-AuthHeaders {
    return @{
        "User-Agent"    = "github-updater-ps1"
        "Accept"        = "application/vnd.github+json"
        "Authorization" = "Bearer $GITHUB_TOKEN"
    }
}

function Invoke-GitHubApi {
    param([string]$Url)
    return Invoke-RestMethod -Uri $Url -Headers (Get-AuthHeaders) -TimeoutSec 30
}

# ----- get remote version ------------------------------------
function Get-RemoteVersion {
    if ($USE_RELEASES) {
        $release = Invoke-GitHubApi "$API_BASE/releases/latest"
        return [PSCustomObject]@{ Id = $release.tag_name; DownloadUrl = $release.zipball_url }
    } else {
        $commit = Invoke-GitHubApi "$API_BASE/commits/$GITHUB_BRANCH"
        $sha = $commit.sha
        $zipUrl = "$API_BASE/zipball/$GITHUB_BRANCH"
        return [PSCustomObject]@{ Id = $sha; DownloadUrl = $zipUrl }
    }
}

# ----- get local version -------------------------------------
function Get-LocalVersion {
    if (Test-Path $VERSION_FILE) {
        return (Get-Content $VERSION_FILE -Raw).Trim()
    }
    return $null
}

# ----- download and extract ----------------------------------
function Install-Update {
    param([string]$DownloadUrl, [string]$VersionId)

    $tmpZip = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gh_update_$([guid]::NewGuid()).zip")
    $tmpDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gh_update_$([guid]::NewGuid())")

    try {
        Write-Log "Downloading from $DownloadUrl ..."
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            # Resolve the GitHub API redirect to get the real CDN URL, then download without auth header
            $redirect = Invoke-WebRequest -Uri $DownloadUrl -Headers (Get-AuthHeaders) -MaximumRedirection 0 -ErrorAction SilentlyContinue -UseBasicParsing
            $cdnUrl = $redirect.Headers['Location']
            if ($cdnUrl) {
                Invoke-WebRequest -Uri $cdnUrl -OutFile $tmpZip -TimeoutSec 120 -UseBasicParsing
            } else {
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $tmpZip -Headers (Get-AuthHeaders) -TimeoutSec 120 -UseBasicParsing
            }
        } finally {
            $ProgressPreference = $prevProgress
        }

        Write-Log "Extracting archive ..."
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

        # GitHub zips have a single top-level folder; find it
        $innerFolder = Get-ChildItem -Path $tmpDir -Directory | Select-Object -First 1
        if (-not $innerFolder) { throw "Extracted archive contains no folder." }

        # Ensure destination exists
        if (-not (Test-Path $INSTALL_PATH)) {
            New-Item -ItemType Directory -Path $INSTALL_PATH -Force | Out-Null
        }

        # Remove only items that are also present in the repo (leaves unrelated files/folders untouched)
        Write-Log "Cleaning repo-managed items from destination ..."
        Get-ChildItem -Path $innerFolder.FullName -Force | ForEach-Object {
            $target = Join-Path $INSTALL_PATH $_.Name
            if (Test-Path $target) {
                Remove-Item -Path $target -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Log "Copying files to $INSTALL_PATH ..."
        Copy-Item -Path "$($innerFolder.FullName)\*" -Destination $INSTALL_PATH -Recurse -Force

        # Save new version
        Set-Content -Path $VERSION_FILE -Value $VersionId -Encoding UTF8 -NoNewline
        Write-Log "Update complete. Version: $VersionId"
    }
    finally {
        Remove-Item -Path $tmpZip -ErrorAction SilentlyContinue
        Remove-Item -Path $tmpDir -Recurse -ErrorAction SilentlyContinue
    }
}

# ----- main --------------------------------------------------
try {
    Write-Log "=== GitHub Updater started ==="
    $remote = Get-RemoteVersion
    $local  = Get-LocalVersion

    Write-Log "Remote version : $($remote.Id)"
    Write-Log "Local  version : $(if ($local) { $local } else { '(none)' })"

    if ($remote.Id -ne $local) {
        Write-Log "New version detected - starting download ..."
        Install-Update -DownloadUrl $remote.DownloadUrl -VersionId $remote.Id
    } else {
        Write-Log "Already up-to-date."
    }
}
catch {
    Write-Log ('ERROR: ' + $_) 'ERROR'
    exit 1
}
