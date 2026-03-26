public with sharing class PEInvoiceAttachByRecord {
    @InvocableMethod
    public static List<Id> generateAndAttach(List<hed__Program_Enrollment__c> enrollments) {
        List<Id> outIds = new List<Id>();
        for (hed__Program_Enrollment__c pe : enrollments) {
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);
            ProgramEnrollmentInvoiceController.enqueueStudentConfirmationAfterInvoice(pe.Id);
            outIds.add(pe.Id);
        }
        return outIds;
    }
}