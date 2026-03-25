trigger CourseEnrollmentInvoiceTrigger on hed__Course_Enrollment__c (after insert, after update) {

    // Prevent recursion
    if (TriggerHandlerHelper.isAlreadyRunning('CourseEnrollmentInvoiceTrigger')) {
        return;
    }
    TriggerHandlerHelper.markRunning('CourseEnrollmentInvoiceTrigger');

    Set<Id> termEnrollmentIds = new Set<Id>();

    for (hed__Course_Enrollment__c ce : Trigger.new) {
        if (ce.Term_Enrollment__c != null) {
            termEnrollmentIds.add(ce.Term_Enrollment__c);
        }
    }

    // If Term Enrollment lookup changed, include old as well.
    if (Trigger.isUpdate) {
        for (hed__Course_Enrollment__c ceOld : Trigger.old) {
            if (ceOld.Term_Enrollment__c != null) {
                termEnrollmentIds.add(ceOld.Term_Enrollment__c);
            }
        }
    }

    if (termEnrollmentIds.isEmpty()) return;

    Map<Id, Term_Enrollment__c> teMap = new Map<Id, Term_Enrollment__c>([
        SELECT Id, Program_Enrollment__c
        FROM Term_Enrollment__c
        WHERE Id IN :termEnrollmentIds
    ]);

    Set<Id> peIds = new Set<Id>();
    for (Term_Enrollment__c te : teMap.values()) {
        if (te.Program_Enrollment__c != null) peIds.add(te.Program_Enrollment__c);
    }

    if (peIds.isEmpty()) return;

    for (Id peId : peIds) {
        System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(peId));
    }
}

