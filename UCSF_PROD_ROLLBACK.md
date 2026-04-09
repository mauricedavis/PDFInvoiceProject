# ucsf-prod deploy rollback (PDF / enrollee email work)

Use this after a deploy if you need to undo changes in **University of California San Francisco** production (`ucsf-prod`).

## 1. Note the deployment

After each `sf project deploy start`, save the **Deployment Id** from the CLI output (or **Setup → Deployment Status**). Some teams use that for support tickets or to correlate with Salesforce change history.

## 2. Pre-deploy snapshots (metadata rollback)

Before redeploying an older flow from Git, confirm you have a **pre-change** copy. Prod snapshots in this repo:

| Flow (API name) | Pre-deploy snapshot in this repo | Notes |
|-----------------|----------------------------------|--------|
| `Payment_Processing_Marking_Students_as_Paid` | `flow-snapshots/Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_prod_2026-04-08_pre_inline_logo.flow-meta.xml` | Prod immediately before **inline logo** deploy (`UCSF_ImplSci_EmailLogo` static resource + `nameSegment` fix). Roll back **StaticResource** + Apex + flow from Git if undoing. |
| `Payment_Processing_Marking_Students_as_Paid` | `flow-snapshots/Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_prod_2026-04-08.flow-meta.xml` | Prod before first **2026-04-08** payment batch (earlier same-day capture). |
| `Payment_Processing_Marking_Students_as_Paid` | `flow-snapshots/Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_prod_2026-04-07.flow-meta.xml` | Before **`richTextEmailBody`** attempt (plain `emailBody`, raw HTML in Gmail). |
| `Payment_Processing_Marking_Students_as_Paid` | `flow-snapshots/Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_prod_2026-04-09.flow-meta.xml` | Earlier prod capture (payment + enrollee batch deploy). |
| `Program_Enrollment_Notification_to_Enrollee` | `flow-snapshots/Program_Enrollment_Notification_to_Enrollee_PRE_DEPLOY_ucsf_prod_2026-04-09.flow-meta.xml` | Before enrollee / payment-related flow updates in that batch. |

**CLI rollback (one flow at a time):** copy the chosen snapshot over `force-app/main/default/flows/<ApiName>.flow-meta.xml`, ensure `<status>Active</status>` matches what you want, then:

`sf project deploy start -o ucsf-prod -m "Flow:<ApiName>"`  
(use the same `--test-level` / `--tests` pattern your org requires for production).

Ad-hoc CLI retrieves (zip/unzipped) may exist locally under `flow-snapshots/ucsf-prod-rollback/`; canonical rollback copies are the `*_PRE_DEPLOY_ucsf_prod_*.flow-meta.xml` files in `flow-snapshots/`.

## 3. Roll back the **Program Enrollment - Notification to Enrollee** flow (UI)

Salesforce keeps prior flow versions.

1. **Setup → Flows** → open **Program Enrollment - Notification to Enrollee**.
2. Open **Version History** (or the versions list in Flow Builder).
3. **Deactivate** the active version (the one you just deployed).
4. **Activate** the prior version you trust (or redeploy from the pre-deploy snapshot above).

Older Git mirror (v18, for diff or historical reference):  
`flow-snapshots/Program_Enrollment_Notification_to_Enrollee_v18.flow-meta.xml`  
(To deploy v18 from Git: copy that file over `force-app/main/default/flows/Program_Enrollment_Notification_to_Enrollee.flow-meta.xml`, set `<status>Active</status>`, then deploy only that flow with care.)

## 4. Roll back **Payment Processing — Marking Students as Paid** (UI)

1. **Setup → Flows** → open **Payment Processing - Marking Students as Paid** (API: `Payment_Processing_Marking_Students_as_Paid`).
2. **Version History** → deactivate the current active version → activate the previous version, **or** redeploy from the **2026-04-08** snapshot (undo Apex email action) or older snapshots in §2. If reverting the flow only, remove or redeploy **Apex** `PaymentReceivedEmailInvocable` / tests from a prior Git commit so the org stays consistent.

## 5. Roll back **Apex** (student email, invoice PDF, queueable/batch)

Salesforce does not offer one-click “revert deployment” for Apex. Options:

- **Redeploy the previous known-good classes** from Git: `git checkout <commit> --` the paths below (include each `-meta.xml`), then deploy to `ucsf-prod` with the test level your org requires (`RunLocalTests` or `RunSpecifiedTests`).
- **Invoice / course lines on PDF** (Mar 27 2026 change): affected classes are  
  `ProgramEnrollmentInvoiceController`, `ProgramEnrollmentInvoiceQueueable`, `ProgramEnrollmentInvoiceBatch`, and tests `ProgramEnrollmentInvoiceController_Tests`. Revert those together so readiness + stale-invoice logic stays consistent.
- **Student confirmation email**: `ProgramEnrollmentStudentEmail`, `ProgramEnrollmentStudentEmailQueueable`, `PEInvoiceActionOne`, etc.
- **Payment received (Implementation Science) HTML email**: `PaymentReceivedEmailInvocable`, `PaymentReceivedEmailInvocable_Tests` — revert/deploy together with the Payment flow if you undo the Apex-based send.
- **Payment email logo**: Static Resource **`ImplemenationScienceLogo`** (org-domain `/resource/...` URL in HTML; no CID). Legacy **`UCSF_ImplSci_EmailLogo`** may still exist in the org if not deleted manually.
- Or deploy from a **branch/tag** that matches pre-change prod.

## 6. Full project rollback

Check out the commit **before** this deploy and run a full deploy to `ucsf-prod` (with the same test level your org requires). Prefer validating in **ucsf-fullsb** first.

## 7. Related doc

See **`FLOW_DEPLOY_SCOPE.md`** for v18 vs v19 behaviour and deploy scope.

---

## Last deploy recorded from this repo (update when you push again)

| When (UTC)        | Org        | Deploy Id          | Components | Tests |
|-------------------|------------|--------------------|------------|-------|
| 2026-04-08        | ucsf-fullsb | `0Afbb00000Bgg2vCAB` | `ProgramEnrollmentStudentEmailQueueable` (skip confirmation when PE `Currently Enrolled`), `ProgramEnrollmentInvoiceController` (`enqueue` skip + test helper), tests | RunSpecifiedTests: StudentEmail + InvoiceController 45/45 pass |
| 2026-04-08        | ucsf-prod  | `0AfPj00000240TJKAY` | Same as prior fullsb row | RunSpecifiedTests: 45/45 pass |
| 2026-04-08        | ucsf-fullsb | `0Afbb00000BgdufCAB` | Apex `PaymentReceivedEmailInvocable` + tests (no logo; enrollment line from Course Connection / offering) | RunSpecifiedTests: `PaymentReceivedEmailInvocable_Tests` 10/10 pass |
| 2026-04-08        | ucsf-prod  | `0AfPj00000240OTKAY` | Same as prior fullsb row | RunSpecifiedTests: `PaymentReceivedEmailInvocable_Tests` 10/10 pass |
| 2026-04-08        | ucsf-fullsb | `0Afbb00000BfimjCAB` | Apex `PaymentReceivedEmailInvocable`, StaticResource `ImplemenationScienceLogo` (+ tests unchanged) | RunSpecifiedTests: `PaymentReceivedEmailInvocable_Tests` 3/3 pass |
| 2026-04-08        | ucsf-prod  | `0AfPj0000023uVxKAI` | Same subset as fullsb row (metadata deploy; org-domain logo URL, no inline attachment) | RunSpecifiedTests: `PaymentReceivedEmailInvocable_Tests` 3/3 pass |
| 2026-04-08        | ucsf-prod  | `0AfPj0000023uAzKAI` | StaticResource `UCSF_ImplSci_EmailLogo`, Apex `PaymentReceivedEmailInvocable` (+ tests), Flow `Payment_Processing_Marking_Students_as_Paid` (inline logo + `nameSegment` fix) | RunSpecifiedTests: 67 pass (+ EnrollmentEmailTemplateConfig_Tests) |
| 2026-04-08        | ucsf-prod  | `0AfPj0000023u2vKAA` | Apex `PaymentReceivedEmailInvocable` (+ tests), Flow `Payment_Processing_Marking_Students_as_Paid` (Apex action for HTML payment email) | RunSpecifiedTests: 66 pass (StudentEmail, InvoiceController, Notify, PaymentReceivedEmail) |
| 2026-04-07        | ucsf-prod  | `0AfPj0000023pmPKAQ` | Flow `Payment_Processing_Marking_Students_as_Paid` (`emailSimple` → **`richTextEmailBody`** for HTML email) | RunSpecifiedTests: 63 pass |
| 2026-04-09        | ucsf-prod  | `0AfPj0000023nz7KAA` | 2 Flows (`Payment_Processing_Marking_Students_as_Paid`, `Program_Enrollment_Notification_to_Enrollee`) | RunSpecifiedTests: 63 pass |
| 2026-03-27 13:54Z | ucsf-prod  | `0AfPj0000022ygTKAQ` | 36         | 74 / 74 pass |
| 2026-03-27 13:15Z | ucsf-prod  | `0AfPj0000022ydFKAQ` | 36         | 74 / 74 pass |
| 2026-03-27 12:57Z | ucsf-prod  | `0AfPj0000022yYPKAY` | 36         | 74 / 74 pass |

Setup path for status: **Setup → Deployment Status** → open the deploy by Id.
