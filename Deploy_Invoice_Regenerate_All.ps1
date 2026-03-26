# Deploy invoice regenerate feature + dependencies in one shot (adjust -target-org as needed).
# Usage: .\Deploy_Invoice_Regenerate_All.ps1
# Requires: Salesforce CLI (sf)

$org = "ucsf-prod"

sf project deploy start --target-org $org --wait 10 `
  --source-dir "force-app/main/default/objects/hed__Program_Enrollment__c/fields/Regenerate_Invoice__c.field-meta.xml" `
  --source-dir "force-app/main/default/classes/ProgramEnrollmentInvoiceController.cls" `
  --source-dir "force-app/main/default/classes/ProgramEnrollmentInvoiceController.cls-meta.xml" `
  --source-dir "force-app/main/default/classes/ProgramEnrollmentInvoiceRegenerateBatch.cls" `
  --source-dir "force-app/main/default/classes/ProgramEnrollmentInvoiceRegenerateBatch.cls-meta.xml" `
  --source-dir "force-app/main/default/classes/PEInvoiceRegenerateInvocable.cls" `
  --source-dir "force-app/main/default/classes/PEInvoiceRegenerateInvocable.cls-meta.xml" `
  --source-dir "force-app/main/default/triggers/ProgramEnrollmentRegenerateInvoiceTrigger.trigger" `
  --source-dir "force-app/main/default/triggers/ProgramEnrollmentRegenerateInvoiceTrigger.trigger-meta.xml" `
  --source-dir "force-app/main/default/classes/ProgramEnrollmentInvoiceController_Tests.cls" `
  --source-dir "force-app/main/default/classes/ProgramEnrollmentInvoiceController_Tests.cls-meta.xml"
