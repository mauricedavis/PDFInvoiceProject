# ============================================
# Push_PDFInvoice_Sequence_Clean.ps1
# Full sequential deploy: Program Enrollment invoice PDF, batch/queueable,
# student + office email, term/course triggers, regenerate-invoice flow.
# ============================================

# Reset to project root so relative paths and `sf project` resolve correctly
cd C:\Users\MauriceJDavis\PDFInvoiceProject

# --- CONFIGURATION ---
$OrgAlias = "ucsf-prod"   # e.g. ucsf-prod — change as needed
$DeployLogDir = "C:\Users\MauriceJDavis\PDFInvoiceProject\logs"

if (-not (Test-Path $DeployLogDir)) {
    New-Item -Path $DeployLogDir -ItemType Directory | Out-Null
}

function Deploy-Component {
    param (
        [string]$Path,
        [string]$Label
    )

    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Yellow
    Write-Host "Deploying: $Label" -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Yellow

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeLabel = ($Label -replace '[\\/:*?"<>| ]', "_")
    $logFile = Join-Path $DeployLogDir ("Deploy_" + $safeLabel + "_" + $timestamp + ".log")

    try {
        Write-Host "Running: sf project deploy start --target-org $OrgAlias --source-dir $Path --verbose" -ForegroundColor DarkGray

        $output = & sf project deploy start --target-org $OrgAlias --source-dir $Path --verbose 2>&1 |
            Tee-Object -FilePath $logFile

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Deployment failed for $Label" -ForegroundColor Red
            Write-Host "Check log: $logFile" -ForegroundColor Red
            Write-Host $output -ForegroundColor DarkGray
            exit 1
        }
        else {
            Write-Host "Successfully deployed $Label" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "ERROR deploying $Label. See $logFile" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host " PDF Invoice / Enrollment — full push" -ForegroundColor Yellow
Write-Host " Target Org: $OrgAlias" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

# --- 1) Custom fields (hed__Program_Enrollment__c) ---
Deploy-Component "force-app\main\default\objects\hed__Program_Enrollment__c\fields\Regenerate_Invoice__c.field-meta.xml" "Field Regenerate_Invoice__c"
Deploy-Component "force-app\main\default\objects\hed__Program_Enrollment__c\fields\Last_Invoice_ContentVersion_Id__c.field-meta.xml" "Field Last_Invoice_ContentVersion_Id__c"
Deploy-Component "force-app\main\default\objects\hed__Program_Enrollment__c\fields\Invoice_Last_Sent__c.field-meta.xml" "Field Invoice_Last_Sent__c"

# --- 2) Visualforce (PDF) — before Apex that calls Page.* ---
Deploy-Component "force-app\main\default\pages\PDFInvoiceActionOne.page" "Page PDFInvoiceActionOne"
Deploy-Component "force-app\main\default\pages\ProgramEnrollmentInvoicePDF.page" "Page ProgramEnrollmentInvoicePDF"

# --- 3) Core Apex (dependency order) ---
Deploy-Component "force-app\main\default\classes\TriggerHandlerHelper.cls" "TriggerHandlerHelper"
Deploy-Component "force-app\main\default\classes\EmailActivityLogUtil.cls" "EmailActivityLogUtil"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceController.cls" "ProgramEnrollmentInvoiceController"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceBatch.cls" "ProgramEnrollmentInvoiceBatch"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceRegenerateBatch.cls" "ProgramEnrollmentInvoiceRegenerateBatch"
Deploy-Component "force-app\main\default\classes\PEInvoiceRegenerateInvocable.cls" "PEInvoiceRegenerateInvocable"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentStudentEmail.cls" "ProgramEnrollmentStudentEmail"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentStudentEmailQueueable.cls" "ProgramEnrollmentStudentEmailQueueable"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentOfficeNotify.cls" "ProgramEnrollmentOfficeNotify"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentNotificationActions.cls" "ProgramEnrollmentNotificationActions"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceQueueable.cls" "ProgramEnrollmentInvoiceQueueable"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceFlowAction.cls" "ProgramEnrollmentInvoiceFlowAction"
Deploy-Component "force-app\main\default\classes\InvocablePEInvoice.cls" "InvocablePEInvoice"
Deploy-Component "force-app\main\default\classes\InvocablePEInvoiceAttach.cls" "InvocablePEInvoiceAttach"
Deploy-Component "force-app\main\default\classes\PEInvoiceAttachByRecord.cls" "PEInvoiceAttachByRecord"
Deploy-Component "force-app\main\default\classes\PEInvoiceFlowByRecord.cls" "PEInvoiceFlowByRecord"
Deploy-Component "force-app\main\default\classes\PEInvoiceActionOne.cls" "PEInvoiceActionOne"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceTriggerHandler.cls" "ProgramEnrollmentInvoiceTriggerHandler"

# --- 4) Triggers (after all referenced Apex) ---
Deploy-Component "force-app\main\default\triggers\TermEnrollmentInvoiceTrigger.trigger" "TermEnrollmentInvoiceTrigger"
Deploy-Component "force-app\main\default\triggers\CourseEnrollmentInvoiceTrigger.trigger" "CourseEnrollmentInvoiceTrigger"
Deploy-Component "force-app\main\default\triggers\ProgramEnrollmentInvoiceTrigger.trigger" "ProgramEnrollmentInvoiceTrigger"
Deploy-Component "force-app\main\default\triggers\ProgramEnrollmentRegenerateInvoiceTrigger.trigger" "ProgramEnrollmentRegenerateInvoiceTrigger"

# --- 5) Tests (sandbox / validation deploys) ---
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceController_Tests.cls" "ProgramEnrollmentInvoiceController_Tests"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentStudentEmail_Tests.cls" "ProgramEnrollmentStudentEmail_Tests"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentNotify_Tests.cls" "ProgramEnrollmentNotify_Tests"

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "All components deployed successfully." -ForegroundColor Green
Write-Host "Logs: $DeployLogDir" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green