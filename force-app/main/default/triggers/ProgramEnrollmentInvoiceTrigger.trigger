trigger ProgramEnrollmentInvoiceTrigger on hed__Program_Enrollment__c (after insert) {

    // Prevent recursion
    if (TriggerHandlerHelper.isAlreadyRunning('ProgramEnrollmentInvoiceTrigger')) {
        return;
    }

    TriggerHandlerHelper.markRunning('ProgramEnrollmentInvoiceTrigger');

    List<Id> peIds = new List<Id>();
    List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest> officeNotifyRequests = new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>();

    for (hed__Program_Enrollment__c pe : Trigger.new) {
        if (pe.Id != null) {
            peIds.add(pe.Id);
            ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req = new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
            req.programEnrollmentId = pe.Id;
            officeNotifyRequests.add(req);
        }
    }

    if (!officeNotifyRequests.isEmpty() && !Test.isRunningTest()) {
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(officeNotifyRequests);
    }

    // Invoice generation is triggered when Term/Course Enrollment records are created/updated,
    // so the invoice includes the final course enrollments.
}