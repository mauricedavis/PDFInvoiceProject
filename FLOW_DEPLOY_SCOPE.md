# Program Enrollment notification flow — deploy scope

## v18 vs v19 (revert path)

- **In Salesforce:** A metadata deploy of the enrollee flow does **not** delete older definitions. Each deploy adds a **new version**; **v18 stays in the org** under **Setup → Flows → Program Enrollment - Notification to Enrollee → Version History**. To roll back in-org: open the flow, deactivate the current version, then **Activate** version 18 (or whichever you need).
- **In Git:** A frozen copy of the retrieved **v18** definition (including `emailSimple` and `sfProgramEnrollmentId__c` on `PEInvoiceActionOne`) lives at **`flow-snapshots/Program_Enrollment_Notification_to_Enrollee_v18.flow-meta.xml`**. That folder is **not** under `force-app/` and is listed in **`.forceignore`** so normal deploys only push **v19** from `force-app/.../Program_Enrollment_Notification_to_Enrollee.flow-meta.xml`. To restore v18 from Git into an org, copy the snapshot into `force-app/...` (replace the deploy file), set `<status>Active</status>` if needed, and deploy deliberately.

## Source of truth

- **Active ucsf-prod behaviour** was retrieved into `retrieved_prod_flow/` for comparison. Repo flow **`force-app/main/default/flows/Program_Enrollment_Notification_to_Enrollee.flow-meta.xml`** is **v19** (aligned with that structure plus the fixes below). **v18** is preserved only in **Version History** (org) and **`flow-snapshots/`** (Git).

## v20 changes (flow path to PEInvoiceActionOne)

- **Invoice branch** (`Invoice_created__c = false`): `Get_ContentDocumentLink` now uses **`$Record.Id`** (same as post–Copy FA PE files), **`assignNullValuesIfNoRecordsFound = true`**, and a **decision** routes either through the existing ContentVersion + PE updates or, when no link exists, **`Set_Invoice_Created_No_CDL_On_PE`** then **`PEInvoiceActionOne`**. This avoids flow **faults** when `sfProgramEnrollmentId__c` was blank or files were never linked to that value.
- **Apex:** `PEInvoiceActionOne` uses **try/finally** so `enqueueStudentConfirmationAfterInvoice` still runs if `generateAttachAndEmail` ever throws outside its internal catch.

## v19 changes (student confirmation + invoice PDF)

1. **Removed** the Flow **Send Email** (`emailSimple`) step that used `attachmentIdCollection` with the same **Enrollment Confirmation** template Id as Apex. That same-txn send logged an `EmailMessage` with `EmailTemplateId` set, so **`ProgramEnrollmentStudentEmail.sendStudentEmailInternal` dedupe skipped the queueable**—students often received only the Flow email, which showed **one** PDF attachment.
2. **Student confirmation** is delivered only via **`PEInvoiceActionOne` → `ProgramEnrollmentInvoiceController.enqueueStudentConfirmationAfterInvoice` → `ProgramEnrollmentStudentEmailQueueable`** (after commit), which attaches **both** PDFs.
3. **`PEInvoiceActionOne.ProgramEnrollmentId`** is wired to **`$Record.Id`** (not `sfProgramEnrollmentId__c`) so invoice generation and enqueue target the correct Program Enrollment.

## Scoped deploy guidance

- **Do not** deploy an older copy of `Program_Enrollment_Notification_to_Enrollee` from another branch without diffing against this file; overwriting the org can remove trigger filters, async paths, or attachment behaviour.
- Prefer **explicit manifest** deploys that list this flow only when you intend to update enrollee notifications.

## Manual regression (sandbox or prod after deploy)

1. Use one **Program Enrollment** where **Invoice emailed** is false and both **Course Registration Responses** and **Invoice_** PDFs exist on the PE (or let the flow generate the invoice).
2. Fire the flow path (same criteria as production).
3. Open the resulting **EmailMessage** on the PE: confirm **two** PDF attachments (responses + invoice).
