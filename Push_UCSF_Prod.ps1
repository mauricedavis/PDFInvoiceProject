<#
.SYNOPSIS
  Deploy force-app/main/default to Salesforce with explicit human checkpoints.

.DESCRIPTION
  Confirms org connection, pauses for you to press Enter before deploy, then runs
  sf project deploy start. Default target is ucsf-prod.

.PARAMETER OrgAlias
  Salesforce CLI org alias (default: ucsf-prod).

.PARAMETER ProjectRoot
  Path to PDFInvoiceProject root. Default: this script's directory.

.PARAMETER QuickTests
  Use RunSpecifiedTests with ProgramEnrollmentStudentEmail_Tests,
  ProgramEnrollmentInvoiceController_Tests, ProgramEnrollmentNotify_Tests,
  EnrollmentEmailTemplateConfig_Tests, and PaymentReceivedEmailInvocable_Tests (faster).
  Recommended for this repo. If deploy fails on coverage, run again without -QuickTests.

.PARAMETER ValidateOnly
  Validation deploy only (--dry-run); nothing is committed to the org.

.PARAMETER NoPause
  Skip Read-Host prompts (for scripted runs).

.EXAMPLE
  .\Push_UCSF_Prod.ps1

.EXAMPLE
  .\Push_UCSF_Prod.ps1 -QuickTests

.EXAMPLE
  .\Push_UCSF_Prod.ps1 -ValidateOnly -QuickTests
#>

[CmdletBinding()]
param(
    [string] $OrgAlias = "ucsf-prod",
    [string] $ProjectRoot = "",
    [switch] $QuickTests,
    [switch] $ValidateOnly,
    [switch] $NoPause
)

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $ProjectRoot = $PSScriptRoot
    }
    else {
        $ProjectRoot = (Get-Location).Path
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# PowerShell 7+: native commands (sf) write "CLI update available" to stderr; that must not abort the script.
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$sourceDir = Join-Path $ProjectRoot "force-app\main\default"
if (-not (Test-Path $sourceDir)) {
    Write-Error "Source folder not found: $sourceDir"
}

Set-Location $ProjectRoot

Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host " Deploy target: $OrgAlias" -ForegroundColor Yellow
Write-Host " Project root:  $ProjectRoot" -ForegroundColor Yellow
Write-Host " Source:        $sourceDir" -ForegroundColor Yellow
if ($ValidateOnly) { Write-Host " Mode:          VALIDATE ONLY (dry-run)" -ForegroundColor Magenta }
elseif ($QuickTests) { Write-Host " Tests:         RunSpecifiedTests (StudentEmail + InvoiceController + Notify)" -ForegroundColor Cyan }
else { Write-Host " Tests:         RunLocalTests (full org test run)" -ForegroundColor Cyan }
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "Checking org connection..." -ForegroundColor DarkGray
# Do not merge stderr with 2>&1 here; that can surface CLI warnings as terminating errors under $ErrorActionPreference Stop.
& sf org display --target-org $OrgAlias
if ($LASTEXITCODE -ne 0) {
    Write-Error "Org '$OrgAlias' not available. Run: sf org login web --alias $OrgAlias"
}

if (-not $NoPause) {
    Write-Host ""
    Write-Host "You are in the middle of the push: review the org above." -ForegroundColor Green
    $null = Read-Host "Press Enter to continue to deploy (or Ctrl+C to cancel)"
}

$logDir = Join-Path $ProjectRoot "logs"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logDir ("Deploy_ucsf-prod_" + $timestamp + ".log")

$sfArgs = @(
    "project", "deploy", "start",
    "--source-dir", $sourceDir,
    "--target-org", $OrgAlias,
    "--wait", "90"
)

if ($ValidateOnly) {
    $sfArgs += "--dry-run"
}

if ($QuickTests) {
    $sfArgs += @(
        "--test-level", "RunSpecifiedTests",
        "--tests", "ProgramEnrollmentStudentEmail_Tests",
        "--tests", "ProgramEnrollmentInvoiceController_Tests",
        "--tests", "ProgramEnrollmentNotify_Tests",
        "--tests", "EnrollmentEmailTemplateConfig_Tests",
        "--tests", "PaymentReceivedEmailInvocable_Tests"
    )
}
else {
    $sfArgs += @("--test-level", "RunLocalTests")
}

Write-Host ""
Write-Host "Running: sf $($sfArgs -join ' ')" -ForegroundColor DarkGray
Write-Host "Log file: $logFile" -ForegroundColor DarkGray
Write-Host ""

if (-not $NoPause) {
    $null = Read-Host "Final checkpoint - Press Enter to start deploy (or Ctrl+C to cancel)"
}

# Windows PowerShell 5.1: 2>&1 turns sf stderr (e.g. CLI update notice) into ErrorRecords; Stop would abort here.
# PowerShell 7 can use $PSNativeCommandUseErrorActionPreference = $false; Continue works for both.
$deployExitCode = -1
$previousEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & sf @sfArgs 2>&1 | Tee-Object -FilePath $logFile
    $deployExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousEap
}

Write-Host ""
if ($deployExitCode -eq 0) {
    Write-Host "Deploy finished successfully." -ForegroundColor Green
}
else {
    Write-Host ("Deploy failed (exit " + $deployExitCode + "). See log: " + $logFile) -ForegroundColor Red
}

exit $deployExitCode
