# ==============================================
# Run_PDFInvoice_Tests.ps1
# Author: Maurice Davis & GPT-5
# Purpose: Run Apex tests for PDF Invoice components.
# ==============================================

# --------- CONFIGURATION ---------
$TargetOrg = "ucsfsandbox"
$TestClass = "ProgramEnrollmentInvoiceController_Tests"
$LogFolder = ".\logs"

# Ensure logs directory exists
if (-not (Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder | Out-Null
}

# Generate timestamped log filename
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = "$LogFolder\ApexTestRun_$($TestClass)_$($Timestamp).log"

Write-Host ""
Write-Host "============================================"
Write-Host " Running Apex Tests for: $TestClass"
Write-Host " Target Org: $TargetOrg"
Write-Host " Log File: $LogFile"
Write-Host "============================================"
Write-Host ""

# --------- EXECUTION ---------
try {
    # Run Apex Test using Salesforce CLI
    $Cmd = "sf apex run test --target-org $TargetOrg --tests $TestClass --result-format human --wait 10 --verbose"
    Write-Host "Executing command: $Cmd"
    Write-Host ""

    # Execute command and capture output
    $Result = Invoke-Expression $Cmd 2>&1

    # Display CLI output
    Write-Host "========= CLI OUTPUT ========="
    Write-Host $Result
    Write-Host "=============================="

    # Save to log file
    $Result | Out-File -FilePath $LogFile -Encoding UTF8

    # --------- STATUS CHECK ---------
    if ($Result -match "Test Run Failures" -or $Result -match "Fail" -or $Result -match "Error") {
        Write-Host ""
        Write-Host "Some tests failed. Check log file: $LogFile"
    }
    elseif ($Result -match "Success" -or $Result -match "All tests passed") {
        Write-Host ""
        Write-Host "All tests passed successfully!"
    }
    else {
        Write-Host ""
        Write-Host "Test status unclear. Review output for details."
    }

}
catch {
    Write-Host ""
    Write-Host "Error running Apex tests: $($_.Exception.Message)"
}
finally {
    Write-Host ""
    Write-Host "Logs written to: $LogFile"
}