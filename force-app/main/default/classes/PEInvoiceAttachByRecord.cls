public with sharing class PEInvoiceAttachByRecord {
    @InvocableMethod(
        label='Generate Invoice PDF (Attach Only)',
        description='Render invoice PDF for hed__Program_Enrollment__c and attach to the record (no email).'
    )
    public static List<Id> generateAndAttach(List<hed__Program_Enrollment__c> enrollments) {
        List<Id> outIds = new List<Id>();
        for (hed__Program_Enrollment__c pe : enrollments) {
            outIds.add(
                ProgramEnrollmentInvoiceController.generateAndAttach(pe.Id)
            );
        }
        return outIds;
    }
}