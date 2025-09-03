public with sharing class ProgramEnrollmentInvoiceFlowActions_AttachOnly {
    @InvocableMethod(
        label='Generate Invoice PDF (Attach Only)',
        description='Renders PDF for hed__Program_Enrollment__c and attaches it.'
    )
    public static List<Id> generateAndAttach(List<Id> programEnrollmentIds) {
        List<Id> result = new List<Id>();
        for (Id peId : programEnrollmentIds) {
            result.add(ProgramEnrollmentInvoiceController.generateAndAttach(peId));
        }
        return result;
    }
}