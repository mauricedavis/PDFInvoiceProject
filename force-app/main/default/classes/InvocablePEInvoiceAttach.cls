public with sharing class InvocablePEInvoiceAttach {
    @InvocableMethod
    public static List<Id> generateAndAttach(List<Id> programEnrollmentIds) {
        List<Id> outIds = new List<Id>();
        for (Id peId : programEnrollmentIds) {
            outIds.add(ProgramEnrollmentInvoiceController.generateAndAttach(peId));
        }
        return outIds;
    }
}