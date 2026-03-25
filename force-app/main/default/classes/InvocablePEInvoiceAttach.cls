public with sharing class InvocablePEInvoiceAttach {
    @InvocableMethod
    public static List<Id> generateAndAttach(List<Id> programEnrollmentIds) {
        List<Id> outIds = new List<Id>();
        for (Id peId : programEnrollmentIds) {
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(peId);
            outIds.add(peId);
        }
        return outIds;
    }
}