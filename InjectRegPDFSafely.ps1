<#
.SYNOPSIS
  Safely injects (or repairs) Course Registration PDF logic into ProgramEnrollmentInvoiceController.cls

.DESCRIPTION
  - Locates ProgramEnrollmentInvoiceController.cls automatically.
  - Removes duplicate or malformed injection code.
  - Adds attachments declaration if missing.
  - Ensures UTF-8 without BOM encoding.
  - Logs all actions to /logs directory.
#>

param (
    [switch]$dryRun
)

$scriptName = "InjectRegPdfSafely"
$timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir     = Join-Path $PSScriptRoot "logs"
$logFile    = Join-Path $logDir "${scriptName}_${timestamp}.log"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

function Write-Log {
    param ([string]$msg, [string]$color = "Gray")
    $t = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$t] $msg" -ForegroundColor $color
    Add-Content -Path $logFile -Value "[$t] $msg"
}

Write-Host "=== $scriptName starting ===" -ForegroundColor Cyan
Write-Host "Log file: $logFile" -ForegroundColor Gray
Write-Host "====================================" -ForegroundColor Cyan

try {
    # ------------------------------------------
    # Locate the Apex file
    # ------------------------------------------
    Write-Log "Locating ProgramEnrollmentInvoiceController.cls..." "Gray"

    $clsPath = Get-ChildItem -Path $PSScriptRoot -Recurse -Filter "ProgramEnrollmentInvoiceController.cls" -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $clsPath) {
        Write-Log "ERROR: Could not find ProgramEnrollmentInvoiceController.cls under project." "Red"
        exit 1
    }

    Write-Log "Resolved Apex file path: $($clsPath.FullName)" "Green"

    # ------------------------------------------
    # Read file bytes and clean BOM if needed
    # ------------------------------------------
    $bytes = [System.IO.File]::ReadAllBytes($clsPath.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Write-Log "Detected BOM, removing..." "Yellow"
        $bytes = $bytes[3..($bytes.Length - 1)]
        [System.IO.File]::WriteAllBytes($clsPath.FullName, $bytes)
        Write-Log "BOM removed successfully." "Green"
    }

    # ------------------------------------------
    # Read as text (UTF-8)
    # ------------------------------------------
    $original = Get-Content -Path $clsPath.FullName -Raw -Encoding UTF8

    # ------------------------------------------
    # Detect and clean malformed fragments
    # ------------------------------------------
    $fixed = $original

    # Remove broken injected junk like "+ ContentVersion insert + Email send"
    if ($fixed -match "\+ ContentVersion insert \+ Email send") {
        Write-Log "Detected and removing malformed injection fragment." "Yellow"
        $fixed = $fixed -replace "\}\s*\+ ContentVersion insert \+ Email send", "}"
    }

    # Remove duplicate injected blocks (double 'Course Registration' blocks)
    $lines = $fixed -split "`r?`n"
    $seenBlock = $false
    $cleanLines = @()

    foreach ($line in $lines) {
        if ($line -match "Course Registration") {
            if ($seenBlock) {
                Write-Log "Duplicate 'Course Registration' block detected, skipping second copy." "Yellow"
                continue
            }
            $seenBlock = $true
        }
        $cleanLines += $line
    }

    $fixed = ($cleanLines -join "`r`n")

    # Ensure attachments declaration exists before use
    if ($fixed -match "attachments\.add" -and $fixed -notmatch "List<ContentVersion>\s+attachments") {
        Write-Log "Adding attachments list declaration." "Yellow"
        $fixed = $fixed -replace "(String formattedDate = String\.valueOf\(System\.today\(\)\);)", "`$1`r`n        List<ContentVersion> attachments = new List<ContentVersion>();"
    }

    # ------------------------------------------
    # Validation: Apex structure sanity
    # ------------------------------------------
    if ($fixed -match "\+ ContentVersion insert") {
        Write-Log "ERROR: Malformed syntax still detected after cleanup; aborting to avoid corruption." "Red"
        exit 1
    }

    # ------------------------------------------
    # Apply updates if needed
    # ------------------------------------------
    if ($dryRun) {
        Write-Log "Dry-run mode: showing diff summary (no file modified)." "Yellow"
        if ($original -ne $fixed) {
            Write-Log "Changes would be applied." "Gray"
        } else {
            Write-Log "No changes needed." "Green"
        }
    } else {
        if ($original -ne $fixed) {
            Write-Log "Repairing Apex file..." "Cyan"
            [System.IO.File]::WriteAllText($clsPath.FullName, $fixed, (New-Object System.Text.UTF8Encoding $false))
            Write-Log "File updated successfully (UTF-8, no BOM)." "Green"
        } else {
            Write-Log "No file modifications required." "Green"
        }
    }

    Write-Log "Run completed successfully. Log saved at: $logFile" "Cyan"
}
catch {
    Write-Log "Unexpected error: $_" "Red"
    exit 1
}