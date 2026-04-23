# Rollback: Term Payment duplicate guards (flows + Apex)

This repo includes **record-triggered flows** and an **Opportunity before-insert** guard for duplicate Term Payment opportunities. Use the steps below if you need to reduce risk quickly or fully revert.

## Git reference tags (this repository)

| Tag | Commit | Use when |
|-----|--------|----------|
| `release/term-payment-guards-2026-04-24` | `41df390` | Current shipped behavior (FA orphan delete + blocker + flow v42/v4). |
| `rollback/term-payment-before-fa-orphan-delete` | `ddbbe49` | Remove **only** the “delete no-FA orphan when FA inserts” behavior; keep Apex blocker + flows. |
| `rollback/term-payment-before-apex` | `39a1300` | Remove **Apex + trigger**; keep **flow-only** changes (v42 / Calc Fees v4). |
| `rollback/term-payment-flows-v41-dedupe` | `f349f08` | Flow v41 (newest canonical + dedupe, no FA preference) + earlier Calc Fees v3. |

List tags: `git tag -l 'rollback/*' 'release/*'`

Checkout a snapshot locally: `git checkout rollback/term-payment-before-apex`

## Fastest mitigation (no deploy): deactivate the trigger

The Apex logic runs from **`OpportunityTermPaymentDuplicateTrigger`**.

1. **Setup** → **Apex Triggers** → open **OpportunityTermPaymentDuplicateTrigger** → **Edit** → uncheck **Is Active** → **Save**.

This stops insert blocking and orphan deletion **immediately**. Flows (`Term_Enrollment_Create`, `Opportunity_Term_Payments_Calc_Fees`) stay as deployed.

## Partial rollback via metadata deploy (from this repo)

Replace `ORG` with `ucsf-prod` or `ucsf-fullsb` as needed. **Do not run deploy until you confirm the org alias.**

### A) Deactivate trigger via source (preferred if you want Git to match org)

1. In `OpportunityTermPaymentDuplicateTrigger.trigger-meta.xml`, set `<status>Inactive</status>`.
2. Deploy only the trigger metadata:

```text
sf project deploy start --target-org ORG --metadata ApexTrigger:OpportunityTermPaymentDuplicateTrigger
```

3. Commit the change when you are ready so GitHub reflects production.

### B) Remove Apex entirely (revert to flow-only)

Deploy from commit `39a1300` (see tag `rollback/term-payment-before-apex`):

```text
git checkout 39a1300 -- force-app/main/default/classes/TermPaymentOpportunityDuplicateBlocker.cls force-app/main/default/classes/TermPaymentOpportunityDuplicateBlocker.cls-meta.xml force-app/main/default/classes/TermPayOppDupBlockerTest.cls force-app/main/default/classes/TermPayOppDupBlockerTest.cls-meta.xml force-app/main/default/triggers/OpportunityTermPaymentDuplicateTrigger.trigger force-app/main/default/triggers/OpportunityTermPaymentDuplicateTrigger.trigger-meta.xml
```

Then delete those six paths from the working tree if you use `git rm` instead—**simplest** is to check out `39a1300`, copy the `classes` + `triggers` paths that should disappear, return to `main`, and remove the blocker files; or use `sf project delete source` for the Apex metadata (destructive).

Practical approach: from `main`, run:

```text
sf project delete source --target-org ORG --metadata ApexClass:TermPaymentOpportunityDuplicateBlocker,ApexClass:TermPayOppDupBlockerTest,ApexTrigger:OpportunityTermPaymentDuplicateTrigger
```

(Requires human confirmation per your deployment rules.) Then remove the same files from Git on a branch and merge.

### C) Revert flows to an older version

Deploy specific flow versions from an older commit:

```text
git checkout f349f08 -- force-app/main/default/flows/Term_Enrollment_Create.flow-meta.xml force-app/main/default/flows/Opportunity_Term_Payments_Calc_Fees.flow-meta.xml
sf project deploy start --target-org ORG --metadata Flow:Term_Enrollment_Create,Flow:Opportunity_Term_Payments_Calc_Fees
```

Then **activate** the desired flow versions in **Setup → Flows**.

## Full snapshot restore

If you saved a **zip or manifest** from the org (Change Set, Workbench retrieve, or `sf project retrieve start`) taken **before** these changes, deploy that bundle to the org after review.

## Components touched by this initiative

| Area | Metadata |
|------|-----------|
| Flows | `Term_Enrollment_Create`, `Opportunity_Term_Payments_Calc_Fees` |
| Apex | `TermPaymentOpportunityDuplicateBlocker`, `TermPayOppDupBlockerTest` |
| Trigger | `OpportunityTermPaymentDuplicateTrigger` |
| Field (earlier) | `Opportunity.FA_Response_URL__c` |

## After any rollback

- Run your **smoke test** (single FA Term Payment path, one Opp).
- Confirm **Setup → Flows** active versions match intent.
- Reconcile **GitHub** with the org (commit deploy results or revert commits on `main`).
