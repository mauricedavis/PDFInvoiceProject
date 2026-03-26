public with sharing class PEInvoiceFlowByRecord {
    @InvocableMethod
    public static List<Id> generateAndEmail(List<hed__Program_Enrollment__c> enrollments) {
        List<Id> outIds = new List<Id>();
        for (hed__Program_Enrollment__c pe : enrollments) {
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id, null);
            ProgramEnrollmentInvoiceController.enqueueStudentConfirmationAfterInvoice(pe.Id);
            outIds.add(pe.Id);
        }
        return outIds;
    }
}