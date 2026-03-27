# PDFInvoiceProject (UCSF)

Salesforce metadata and Apex for **Program Enrollment** invoice PDFs, **Course Registration** (FormAssembly) file handling on the PE, **student confirmation** email (responses + invoice attachments), and **Program Office** notifications.

**Repository:** [github.com/mauricedavis/PDFInvoiceProject](https://github.com/mauricedavis/PDFInvoiceProject)

**Deploy to production (example):** `.\Push_UCSF_Prod.ps1 -OrgAlias ucsf-prod -QuickTests` (see script for prompts and test options).

**Important:** Invoice generation via **Flow invocables** that call `generateAttachAndEmail` must also chain **student confirmation**. `ProgramEnrollmentInvoiceController.enqueueStudentConfirmationAfterInvoice` is invoked from `InvocablePEInvoice`, `InvocablePEInvoiceAttach`, `PEInvoiceActionOne`, `PEInvoiceAttachByRecord`, and `PEInvoiceFlowByRecord` so the same path as **trigger → `ProgramEnrollmentInvoiceQueueable` → batch `finish`** is not required for the two-PDF student email.

---

## March 2026 — production fixes (summary)

Work focused on **ucsf-prod**: student confirmation reliability, enrollee **Flow** behavior, invoice PDF **course line items**, and safe rollback.

### Student confirmation (two PDFs)

- **Root issue:** Flow **v18** used **Send Email** (`emailSimple`) with the same template as Apex; that logged an `EmailMessage` so **`ProgramEnrollmentStudentEmail`** dedupe skipped the queueable, often leaving **only one** attachment (registration PDF, not invoice).
- **v19 / v20 (enrollee flow):** Removed the Flow **emailSimple** step; confirmation is sent via **`PEInvoiceActionOne` → `enqueueStudentConfirmationAfterInvoice` → `ProgramEnrollmentStudentEmailQueueable`**, with template sends using **`EmailFileAttachment`** from `ContentVersion.VersionData` when both PDFs load (fallback to entity attachments).
- **`PEInvoiceActionOne`:** `ProgramEnrollmentId` = **`$Record.Id`**; **`try/finally`** so the queueable is still enqueued if generation throws.
- **NPE fix:** Static **`programOfficeOweaLookupDone`** must be initialized to **`false`** (uninitialized `Boolean` is `null` and breaks `getProgramOfficeOrgWideEmailAddressId`).

### Enrollee Flow — “needs invoice” path (v20)

- **`Get ContentDocumentLink`** now targets **`$Record.Id`**, allows **no rows**, and branches so the flow **does not fault** when **`sfProgramEnrollmentId__c`** is blank or files are only on the PE (still reaches **`PEInvoiceActionOne`**).

### Invoice PDF — course / Course Connection rows

- **Root issue:** **`generateAttachAndEmail`** could create the **first** invoice **before** Course Connections existed → **$0 / empty table**; idempotency then **blocked** regeneration; the invoice queueable **skipped** when a file already existed.
- **Fix:** **Readiness** (same rules as **`ProgramEnrollmentInvoiceQueueable`**) before the **first** PDF from Flow/invocables; **`generateAttachAndEmailForBatch`** for the batch path (readiness already enforced). **Stale detection** removes **`Invoice_%`** files when course rows are newer than the latest invoice file, then regenerates. **Optional** **`Program_Enrollment__c`** on **`hed__Course_Enrollment__c`** added to the course query OR clause where the field exists.

### Ops / rollback

| Doc | Purpose |
|-----|---------|
| [`FLOW_DEPLOY_SCOPE.md`](FLOW_DEPLOY_SCOPE.md) | Enrollee flow v18 vs v19/v20, deploy scope, regression checks |
| [`UCSF_PROD_ROLLBACK.md`](UCSF_PROD_ROLLBACK.md) | Deployment IDs, Flow Version History (e.g. activate **v18**), Apex class rollback list |
| [`flow-snapshots/Program_Enrollment_Notification_to_Enrollee_v18.flow-meta.xml`](flow-snapshots/Program_Enrollment_Notification_to_Enrollee_v18.flow-meta.xml) | Frozen **v18** flow XML for diff / deliberate redeploy (not the active `force-app` path) |

**Salesforce:** deploying the flow creates a **new version**; older versions remain under **Setup → Flows → Version History**.

**Tests:** `ProgramEnrollmentInvoiceController_Tests`, `ProgramEnrollmentStudentEmail_Tests`, and full **`RunLocalTests`** deploys to **ucsf-prod** were used during validation.

### Related implementation notes

- **`CourseEnrollmentInvoiceTriggerCore`:** bulk of **Course Enrollment** trigger logic (invoice queueable fan-out).
- **Draft safety flow:** `Program_Enrollment_Student_Confirmation_Delayed_Safety` — optional delayed **`ProgramEnrollmentStudentEmail`** enqueue (see flow description).

---

# Salesforce DX Project: Next Steps

Now that you’ve created a Salesforce DX project, what’s next? Here are some documentation resources to get you started.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)
