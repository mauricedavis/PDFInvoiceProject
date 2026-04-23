/**
 * Ensures the FormAssembly Term Payment opportunity (FA_Response_URL__c populated) is the one that remains:
 * 1) Before a FA insert, deletes any existing Payment Due Term Payment Opp for the same Term Enrollment that has no FA URL (automation orphan).
 * 2) Blocks new inserts without FA URL when a Payment Due Term Payment Opp already exists for that TE (DB or same batch), or when another row in the batch has FA for that TE.
 */
public with sharing class TermPaymentOpportunityDuplicateBlocker {
    private static final String TERM_PAYMENT_RT = 'Term_Payment';
    private static final String STAGE_PAYMENT_DUE = 'Payment Due';

    public static void beforeInsert(List<Opportunity> newRows) {
        Id termPaymentRtId = resolveTermPaymentRecordTypeId();
        if (termPaymentRtId == null) {
            return;
        }

        deleteNoFaOrphansWhenFaRowInserts(newRows, termPaymentRtId);

        Map<Id, Boolean> teHasFaLinkedRowInBatch = new Map<Id, Boolean>();
        for (Opportunity o : newRows) {
            if (!isTermPaymentPaymentDueCandidate(o, termPaymentRtId)) {
                continue;
            }
            if (String.isNotBlank(o.FA_Response_URL__c)) {
                teHasFaLinkedRowInBatch.put(o.Term_Enrollment__c, true);
            }
        }

        Set<Id> noFaCandidateTeIds = new Set<Id>();
        for (Opportunity o : newRows) {
            if (!isTermPaymentPaymentDueCandidate(o, termPaymentRtId)) {
                continue;
            }
            if (String.isNotBlank(o.FA_Response_URL__c)) {
                continue;
            }
            noFaCandidateTeIds.add(o.Term_Enrollment__c);
        }
        if (noFaCandidateTeIds.isEmpty()) {
            return;
        }

        Set<Id> teWithExistingDb = new Set<Id>();
        for (Opportunity existing : [
            SELECT Term_Enrollment__c
            FROM Opportunity
            WHERE
                Term_Enrollment__c IN :noFaCandidateTeIds
                AND RecordTypeId = :termPaymentRtId
                AND StageName = :STAGE_PAYMENT_DUE
        ]) {
            teWithExistingDb.add(existing.Term_Enrollment__c);
        }

        Set<Id> teClaimedByNoFaInThisBatch = new Set<Id>();
        for (Opportunity o : newRows) {
            if (!isTermPaymentPaymentDueCandidate(o, termPaymentRtId)) {
                continue;
            }
            if (String.isNotBlank(o.FA_Response_URL__c)) {
                continue;
            }
            Id te = o.Term_Enrollment__c;
            if (teWithExistingDb.contains(te)) {
                o.addError(errorMessage());
                continue;
            }
            if (teHasFaLinkedRowInBatch.get(te) == true) {
                o.addError(errorMessage());
                continue;
            }
            if (teClaimedByNoFaInThisBatch.contains(te)) {
                o.addError(errorMessage());
                continue;
            }
            teClaimedByNoFaInThisBatch.add(te);
        }
    }

    /**
     * FormAssembly row is authoritative: remove an older automation-created Opp (same TE, no FA URL)
     * so the FA insert does not leave two rows.
     */
    private static void deleteNoFaOrphansWhenFaRowInserts(List<Opportunity> newRows, Id termPaymentRtId) {
        Set<Id> teIds = new Set<Id>();
        for (Opportunity o : newRows) {
            if (!isTermPaymentPaymentDueCandidate(o, termPaymentRtId)) {
                continue;
            }
            if (String.isNotBlank(o.FA_Response_URL__c)) {
                teIds.add(o.Term_Enrollment__c);
            }
        }
        if (teIds.isEmpty()) {
            return;
        }
        List<Opportunity> orphans = [
            SELECT Id
            FROM Opportunity
            WHERE
                Term_Enrollment__c IN :teIds
                AND RecordTypeId = :termPaymentRtId
                AND StageName = :STAGE_PAYMENT_DUE
                AND (FA_Response_URL__c = NULL OR FA_Response_URL__c = '')
        ];
        if (!orphans.isEmpty()) {
            delete orphans;
        }
    }

    private static Id resolveTermPaymentRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> byDevName = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
        if (!byDevName.containsKey(TERM_PAYMENT_RT)) {
            return null;
        }
        return byDevName.get(TERM_PAYMENT_RT).getRecordTypeId();
    }

    private static Boolean isTermPaymentPaymentDueCandidate(Opportunity o, Id termPaymentRtId) {
        return o.RecordTypeId == termPaymentRtId
            && o.Term_Enrollment__c != null
            && (o.StageName == STAGE_PAYMENT_DUE || String.isBlank(o.StageName));
    }

    private static String errorMessage() {
        return 'A Term Payment opportunity already exists for this term enrollment (or FormAssembly created one in this batch). '
            + 'Do not insert a second Term Payment opportunity without FA Response URL.';
    }
}
