<#
.SYNOPSIS
  Dual PDF Email Update Script
.DESCRIPTION
  This script performs the following:
  - Validates and injects logic via InjectRegPdfSafely.ps1 if necessary
  - Deploys Salesforce metadata to the specified org
  - Runs Apex syntax verification
  - Creates rollback branch and tag on failure
  - Optionally creates a GitHub release on success
#>

# --------------------------
# Configuration
# --------------------------
$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = "$logDir\DualPDFEmailUpdate_$timestamp.log"

# Force target org alias to UCSF sandbox (avoiding wrong default org)
$orgAlias = "ucsfsandbox"
Write-Host "[INFO] Forcing target org alias: $orgAlias" -ForegroundColor Yellow

# Dry run mode
$dryRun = $args -contains "--dry-run"

Write-Host "=== Starting Dual PDF Email Update Script ===" -ForegroundColor Cyan
Write-Host "Log file: $logFile"
Write-Host ("=" * 45) | Tee-Object -FilePath $logFile -Append

# --------------------------
# Helper Functions
# --------------------------
function Write-Log {
    param([string]$msg, [string]$color = "White")
    $timestamped = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg
    Write-Host $timestamped -ForegroundColor $color
    Add-Content -Path $logFile -Value $timestamped
}

# --------------------------
# Pre-deployment step
# --------------------------
Write-Log "Running pre-deployment injection validation..." "Cyan"
if (Test-Path ".\InjectRegPdfSafely.ps1") {
    Write-Log "Executing InjectRegPdfSafely.ps1..." "Gray"
    & ".\InjectRegPdfSafely.ps1" | Tee-Object -FilePath $logFile -Append
} else {
    Write-Log "InjectRegPdfSafely.ps1 not found - skipping injection." "Yellow"
}

Write-Log "Injection script completed." "Green"

# --------------------------
# Deployment Section
# --------------------------
try {
    Write-Log "Starting Salesforce metadata deployment..." "Cyan"

    $deployCmd = "sf project deploy start --source-dir force-app --target-org $orgAlias --verbose"
    if ($dryRun) {
        $deployCmd += " --dry-run"
        Write-Log "[DRY RUN MODE] Running validation only..." "Yellow"
    }

    Write-Log "Running: $deployCmd" "Gray"
    $deployOutput = Invoke-Expression $deployCmd 2>&1 | Tee-Object -FilePath $logFile -Append

    if ($deployOutput -match "Status: Failed") {
        throw "Deployment failed."
    }

    Write-Log "Deployment completed successfully." "Green"
}
catch {
    Write-Log "Deployment or validation failed - initiating rollback..." "Red"

    $rollbackBranch = "rollback_failedDeploy_${timestamp}_$(Get-Random -Maximum 999999)"
    git checkout -b $rollbackBranch | Tee-Object -FilePath $logFile -Append
    git push origin $rollbackBranch | Tee-Object -FilePath $logFile -Append

    $rollbackTag = "rollback_${timestamp}_$(Get-Random -Maximum 999999)"
    git tag $rollbackTag
    git push origin $rollbackTag | Tee-Object -FilePath $logFile -Append

    Write-Log "Rollback branch and tag created ($rollbackBranch, $rollbackTag)." "Yellow"
    Write-Log "SCRIPT SUMMARY: FAILURE" "Red"
    Write-Log "Script failed or rolled back." "Red"
    Write-Host ("=" * 45)
    Write-Host "Run completed. Log saved at: $logFile" -ForegroundColor Cyan
    pause
    exit 1
}

# --------------------------
# Apex Syntax Verification
# --------------------------
try {
    Write-Log "Running Apex syntax verification via test execution..." "Cyan"
    $testResult = sf apex run test --target-org $orgAlias --code-coverage --wait 10 2>&1 | Tee-Object -FilePath $logFile -Append

    if ($testResult -match "Fail") {
        throw "Apex test failures detected."
    }

    Write-Log "Apex syntax verification passed successfully." "Green"
}
catch {
    Write-Log "Apex test run failed or syntax issue detected." "Red"
    Write-Log "SCRIPT SUMMARY: FAILURE" "Red"
    pause
    exit 1
}

# --------------------------
# GitHub Release (on success)
# --------------------------
try {
    Write-Log "Committing changes and preparing release..." "Cyan"
    git add . | Out-Null
    git commit -m "Automated Dual PDF Email Update $timestamp" | Out-Null
    git push origin main | Tee-Object -FilePath $logFile -Append

    $releaseTag = "release_${timestamp}_$(Get-Random -Maximum 9999)"
    git tag $releaseTag
    git push origin $releaseTag | Tee-Object -FilePath $logFile -Append

    Write-Log "GitHub release created successfully with tag $releaseTag." "Green"
}
catch {
    Write-Log "Warning: GitHub release step skipped or failed (non-critical)." "Yellow"
}

# --------------------------
# Summary Line
# --------------------------
Write-Host ("=" * 45)
Write-Host "[SUMMARY] ✅ DualPDFEmailUpdate completed successfully for org alias '$orgAlias' at $timestamp" -ForegroundColor Green
Write-Host "Log saved to: $logFile"
Write-Host ("=" * 45)
pause
exit 0