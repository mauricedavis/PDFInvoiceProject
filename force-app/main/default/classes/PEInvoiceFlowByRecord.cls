public with sharing class PEInvoiceFlowByRecord {
    @InvocableMethod(
        label='Generate & Email Invoice (Program Enrollment)',
        description='Render invoice PDF for hed__Program_Enrollment__c, attach it to the record, and email the student (+ optional org defaults).'
    )
    public static List<Id> generateAndEmail(List<hed__Program_Enrollment__c> enrollments) {
        List<Id> outIds = new List<Id>();
        for (hed__Program_Enrollment__c pe : enrollments) {
            outIds.add(
                ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id, null)
            );
        }
        return outIds;
    }
}