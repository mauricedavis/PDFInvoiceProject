public with sharing class PEInvoiceFlowAttach {
    @InvocableMethod(label='Generate Invoice PDF (Attach Only)', description='Renders PDF for hed__Program_Enrollment__c and attaches it to the record.')
    public static List<Id> generateAndAttach(List<Id> programEnrollmentIds) {
        List<Id> outIds = new List<Id>();
        for (Id peId : programEnrollmentIds) {
            outIds.add(ProgramEnrollmentInvoiceController.generateAndAttach(peId));
        }
        return outIds;
    }
}