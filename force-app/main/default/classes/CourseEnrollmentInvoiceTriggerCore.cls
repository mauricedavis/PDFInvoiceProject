/**
 * Bulk of CourseEnrollmentInvoiceTrigger logic lives here so the trigger stays small
 * (trigger coverage is calculated separately and is harder to reach 75% on long triggers).
 */
public without sharing class CourseEnrollmentInvoiceTriggerCore {

    public static void afterInsertOrUpdate(
        List<hed__Course_Enrollment__c> newRows,
        List<hed__Course_Enrollment__c> oldRows,
        Boolean isUpdate
    ) {
        if (newRows == null || newRows.isEmpty()) {
            return;
        }

        Set<Id> termEnrollmentIds = new Set<Id>();
        Set<Id> directProgramEnrollmentIds = new Set<Id>();

        Map<String, Schema.SObjectField> ceFields = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        Boolean hasHedProgramEnrollment = ceFields.containsKey('hed__Program_Enrollment__c');

        for (hed__Course_Enrollment__c ce : newRows) {
            if (ce.Term_Enrollment__c != null) {
                termEnrollmentIds.add(ce.Term_Enrollment__c);
            }
            if (hasHedProgramEnrollment && ce.get('hed__Program_Enrollment__c') != null) {
                directProgramEnrollmentIds.add((Id) ce.get('hed__Program_Enrollment__c'));
            }
        }

        if (isUpdate && oldRows != null) {
            for (hed__Course_Enrollment__c ceOld : oldRows) {
                if (ceOld.Term_Enrollment__c != null) {
                    termEnrollmentIds.add(ceOld.Term_Enrollment__c);
                }
                if (hasHedProgramEnrollment && ceOld.get('hed__Program_Enrollment__c') != null) {
                    directProgramEnrollmentIds.add((Id) ceOld.get('hed__Program_Enrollment__c'));
                }
            }
        }

        Set<Id> peIds = new Set<Id>();
        peIds.addAll(directProgramEnrollmentIds);

        if (!termEnrollmentIds.isEmpty()) {
            Map<Id, Term_Enrollment__c> teMap = new Map<Id, Term_Enrollment__c>([
                SELECT Id, Program_Enrollment__c
                FROM Term_Enrollment__c
                WHERE Id IN :termEnrollmentIds
            ]);

            for (Term_Enrollment__c te : teMap.values()) {
                if (te.Program_Enrollment__c != null) {
                    peIds.add(te.Program_Enrollment__c);
                }
            }
        }

        if (peIds.isEmpty()) {
            return;
        }

        for (Id peId : peIds) {
            System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(peId));
        }
    }
}
