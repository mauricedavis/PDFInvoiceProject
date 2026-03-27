trigger CourseEnrollmentInvoiceTrigger on hed__Course_Enrollment__c (after insert, after update) {

    if (TriggerHandlerHelper.isAlreadyRunning('CourseEnrollmentInvoiceTrigger')) {
        return;
    }
    TriggerHandlerHelper.markRunning('CourseEnrollmentInvoiceTrigger');

    CourseEnrollmentInvoiceTriggerCore.afterInsertOrUpdate(
        Trigger.new,
        Trigger.isUpdate ? Trigger.old : null,
        Trigger.isUpdate
    );
}
