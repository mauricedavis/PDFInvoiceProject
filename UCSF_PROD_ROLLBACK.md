# ucsf-prod deploy rollback (PDF / enrollee email work)

Use this after a deploy if you need to undo changes in **University of California San Francisco** production (`ucsf-prod`).

## 1. Note the deployment

After each `sf project deploy start`, save the **Deployment Id** from the CLI output (or **Setup → Deployment Status**). Some teams use that for support tickets or to correlate with Salesforce change history.

## 2. Roll back the **Program Enrollment - Notification to Enrollee** flow

Salesforce keeps prior flow versions.

1. **Setup → Flows** → open **Program Enrollment - Notification to Enrollee**.
2. Open **Version History** (or the versions list in Flow Builder).
3. **Deactivate** the active version (the one you just deployed — may be **v20** or later).
4. **Activate** version **18** (last known-good enrollee flow before this morning’s changes), or whichever prior version you trust.

Git mirror of v18 (for diff or a deliberate metadata redeploy):  
`flow-snapshots/Program_Enrollment_Notification_to_Enrollee_v18.flow-meta.xml`  
(To deploy v18 from Git: copy that file over `force-app/main/default/flows/Program_Enrollment_Notification_to_Enrollee.flow-meta.xml`, set `<status>Active</status>`, then deploy only that flow with care.)

## 3. Roll back **Apex** (student email, invoice PDF, queueable/batch)

Salesforce does not offer one-click “revert deployment” for Apex. Options:

- **Redeploy the previous known-good classes** from Git: `git checkout <commit> --` the paths below (include each `-meta.xml`), then deploy to `ucsf-prod` with the test level your org requires (`RunLocalTests` or `RunSpecifiedTests`).
- **Invoice / course lines on PDF** (Mar 27 2026 change): affected classes are  
  `ProgramEnrollmentInvoiceController`, `ProgramEnrollmentInvoiceQueueable`, `ProgramEnrollmentInvoiceBatch`, and tests `ProgramEnrollmentInvoiceController_Tests`. Revert those together so readiness + stale-invoice logic stays consistent.
- **Student confirmation email**: `ProgramEnrollmentStudentEmail`, `ProgramEnrollmentStudentEmailQueueable`, `PEInvoiceActionOne`, etc.
- Or deploy from a **branch/tag** that matches pre-change prod.

## 4. Full project rollback

Check out the commit **before** this deploy and run a full deploy to `ucsf-prod` (with the same test level your org requires). Prefer validating in **ucsf-fullsb** first.

## 5. Related doc

See **`FLOW_DEPLOY_SCOPE.md`** for v18 vs v19 behaviour and deploy scope.

---

## Last deploy recorded from this repo (update when you push again)

| When (UTC)        | Org        | Deploy Id          | Components | Tests |
|-------------------|------------|--------------------|------------|-------|
| 2026-03-27 13:54Z | ucsf-prod  | `0AfPj0000022ygTKAQ` | 36         | 74 / 74 pass |
| 2026-03-27 13:15Z | ucsf-prod  | `0AfPj0000022ydFKAQ` | 36         | 74 / 74 pass |
| 2026-03-27 12:57Z | ucsf-prod  | `0AfPj0000022yYPKAY` | 36         | 74 / 74 pass |

Setup path for status: **Setup → Deployment Status** → open the deploy by Id.
