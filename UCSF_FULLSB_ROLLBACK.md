# ucsf-fullsb rollback (flows deployed 2026-04-08)

## What was deployed

From `force-app/main/default/flows/` to alias **ucsf-fullsb**:

1. **Program_Enrollment_Notification_to_Enrollee** — v21 entry filter `hed__Enrollment_Status__c` **Not equal to** `Currently Enrolled` (stops registration/invoice PDF email from re-firing when **Payment Processing** sets enrolled status). This version matches **repo / intended prod** metadata (simpler entry criteria than the older fullsb-only variant).
2. **Payment_Processing_Marking_Students_as_Paid** — payment-received email to student (Implementation Science scope, OWEA) when Opportunity **Stage** becomes **Full Payment Received**.

## Pre-deploy backups (restore these to roll back)

| Flow | Backup file (frozen XML from org before deploy) |
|------|---------------------------------------------------|
| Program Enrollment - Notification to Enrollee | [flow-snapshots/Program_Enrollment_Notification_to_Enrollee_PRE_DEPLOY_ucsf_fullsb_2026-04-08.flow-meta.xml](flow-snapshots/Program_Enrollment_Notification_to_Enrollee_PRE_DEPLOY_ucsf_fullsb_2026-04-08.flow-meta.xml) |
| Payment Processing: Marking Students as Paid | [flow-snapshots/Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_fullsb_2026-04-08.flow-meta.xml](flow-snapshots/Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_fullsb_2026-04-08.flow-meta.xml) |

## Rollback option 1 — Salesforce UI (fastest)

1. **Setup** → **Flows**.
2. Open the flow → **Version History** (or **View Details and Versions**).
3. Find the version that was active **before** this deploy → **Activate**.

Repeat per flow if you need to revert both.

## Rollback option 2 — CLI deploy of backup files

From the project root, deploy **one** backup at a time (use the path to the file you need):

```powershell
sf project deploy start -o ucsf-fullsb -d "flow-snapshots\Program_Enrollment_Notification_to_Enrollee_PRE_DEPLOY_ucsf_fullsb_2026-04-08.flow-meta.xml"
```

```powershell
sf project deploy start -o ucsf-fullsb -d "flow-snapshots\Payment_Processing_Marking_Students_as_Paid_PRE_DEPLOY_ucsf_fullsb_2026-04-08.flow-meta.xml"
```

After deploy, confirm the restored version is **Active** in Setup → Flows.

## Note on sandbox vs repo

The **Program Enrollment - Notification to Enrollee** backup reflects **ucsf-fullsb as it was before** this push (e.g. **Payment Pending** / **FormAssembly_URL__c** entry logic). The **deployed** definition follows **`force-app/main/default/flows/Program_Enrollment_Notification_to_Enrollee.flow-meta.xml`** so fullsb aligns with the **production-oriented** source in git. If you roll back the enrollee flow only, you return fullsb to the prior sandbox-specific definition.
