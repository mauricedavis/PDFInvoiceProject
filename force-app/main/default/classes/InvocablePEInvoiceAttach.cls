public with sharing class InvocablePEInvoiceAttach {
    @InvocableMethod(label='Generate Invoice PDF (Attach Only)', description='Render invoice PDF for Program Enrollment and attach to the record.')
    public static List<Id> generateAndAttach(List<Id> programEnrollmentIds) {
        List<Id> outIds = new List<Id>();
        for (Id peId : programEnrollmentIds) {
            outIds.add(ProgramEnrollmentInvoiceController.generateAndAttach(peId));
        }
        return outIds;
    }
}
