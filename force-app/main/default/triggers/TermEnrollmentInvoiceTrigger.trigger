trigger TermEnrollmentInvoiceTrigger on Term_Enrollment__c (after insert, after update) {

    // Prevent recursion
    if (TriggerHandlerHelper.isAlreadyRunning('TermEnrollmentInvoiceTrigger')) {
        return;
    }
    TriggerHandlerHelper.markRunning('TermEnrollmentInvoiceTrigger');

    Set<Id> peIds = new Set<Id>();

    for (Term_Enrollment__c te : Trigger.new) {
        if (te.Program_Enrollment__c != null) {
            peIds.add(te.Program_Enrollment__c);
        }
    }

    // If Program Enrollment lookup changed, include the old PE as well.
    if (Trigger.isUpdate) {
        for (Term_Enrollment__c teOld : Trigger.old) {
            if (teOld.Program_Enrollment__c != null) {
                peIds.add(teOld.Program_Enrollment__c);
            }
        }
    }

    if (peIds.isEmpty()) return;

    for (Id peId : peIds) {
        System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(peId));
    }
}

