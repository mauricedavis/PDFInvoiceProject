# ============================================
# Push_PDFInvoice_Sequence.ps1
# Full sequential deploy (same order as Push_PDFInvoice_Sequence_Clean.ps1)
# ============================================

# Reset to project root so relative paths and `sf project` resolve correctly
cd C:\Users\MauriceJDavis\PDFInvoiceProject

# --- CONFIGURATION ---
$ORG_ALIAS = "ucsfsandbox"  # <-- Change if using a different alias
$DEPLOY_LOG_DIR = "C:\Users\MauriceJDavis\PDFInvoiceProject\logs"
if (!(Test-Path $DEPLOY_LOG_DIR)) { New-Item -Path $DEPLOY_LOG_DIR -ItemType Directory | Out-Null }

function Deploy-Component {
    param (
        [string]$Path,
        [string]$Label
    )

    Write-Host ""
    Write-Host "Deploying $Label..." -ForegroundColor Cyan
    $logFile = Join-Path $DEPLOY_LOG_DIR ("Deploy_" + ($Label -replace '[\\/:*?"<>| ]','_') + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

    $deployCmd = "sf project deploy start --target-org $ORG_ALIAS --source-dir `"$Path`" --verbose"
    Write-Host "Running: $deployCmd" -ForegroundColor DarkGray

    try {
        & sf project deploy start --target-org $ORG_ALIAS --source-dir $Path --verbose 2>&1 | Tee-Object -FilePath $logFile
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Deployment failed for $Label — check $logFile" -ForegroundColor Red
            Exit 1
        } else {
            Write-Host "Successfully deployed $Label" -ForegroundColor Green
        }
    } catch {
        Write-Host "ERROR deploying $Label — check $logFile" -ForegroundColor Red
        Exit 1
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host " PDF Invoice / Enrollment — full push" -ForegroundColor Yellow
Write-Host " Target Org: $ORG_ALIAS" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

# --- 1) Custom fields ---
Deploy-Component "force-app\main\default\objects\hed__Program_Enrollment__c\fields\Regenerate_Invoice__c.field-meta.xml" "Field Regenerate_Invoice__c"
Deploy-Component "force-app\main\default\objects\hed__Program_Enrollment__c\fields\Last_Invoice_ContentVersion_Id__c.field-meta.xml" "Field Last_Invoice_ContentVersion_Id__c"
Deploy-Component "force-app\main\default\objects\hed__Program_Enrollment__c\fields\Invoice_Last_Sent__c.field-meta.xml" "Field Invoice_Last_Sent__c"

# --- 2) Visualforce ---
Deploy-Component "force-app\main\default\pages\PDFInvoiceActionOne.page" "Page PDFInvoiceActionOne"
Deploy-Component "force-app\main\default\pages\ProgramEnrollmentInvoicePDF.page" "Page ProgramEnrollmentInvoicePDF"

# --- 3) Core Apex ---
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

# --- 4) Triggers ---
Deploy-Component "force-app\main\default\triggers\TermEnrollmentInvoiceTrigger.trigger" "TermEnrollmentInvoiceTrigger"
Deploy-Component "force-app\main\default\triggers\CourseEnrollmentInvoiceTrigger.trigger" "CourseEnrollmentInvoiceTrigger"
Deploy-Component "force-app\main\default\triggers\ProgramEnrollmentInvoiceTrigger.trigger" "ProgramEnrollmentInvoiceTrigger"
Deploy-Component "force-app\main\default\triggers\ProgramEnrollmentRegenerateInvoiceTrigger.trigger" "ProgramEnrollmentRegenerateInvoiceTrigger"

# --- 5) Tests ---
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentInvoiceController_Tests.cls" "ProgramEnrollmentInvoiceController_Tests"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentStudentEmail_Tests.cls" "ProgramEnrollmentStudentEmail_Tests"
Deploy-Component "force-app\main\default\classes\ProgramEnrollmentNotify_Tests.cls" "ProgramEnrollmentNotify_Tests"

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " All components deployed successfully." -ForegroundColor Green
Write-Host " Logs saved in: $DEPLOY_LOG_DIR" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
