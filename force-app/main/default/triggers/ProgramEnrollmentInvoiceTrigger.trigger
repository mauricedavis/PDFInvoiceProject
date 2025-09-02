trigger ProgramEnrollmentInvoiceTrigger on hed__Program_Enrollment__c (after insert) {
    for (hed__Program_Enrollment__c pe : Trigger.new) {
        // Add a filter if you only want certain statuses to generate invoices.
        // if (pe.hed__Enrollment_Status__c != 'Pending Payment') continue;
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id, null);
    }
}