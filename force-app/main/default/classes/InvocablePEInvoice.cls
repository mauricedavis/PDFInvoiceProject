public with sharing class InvocablePEInvoice {
    @InvocableMethod(label='Generate, Attach & Email Invoice' description='Generates the invoice PDF, attaches it to Program Enrollment, emails the student, updates audit fields, and logs EmailMessage.')
    public static List<Id> generateAndEmail(List<Id> programEnrollmentIds) {
        List<Id> results = new List<Id>();
        if (programEnrollmentIds == null) return results;
        for (Id peId : programEnrollmentIds) {
            if (peId == null) continue;
            results.add(ProgramEnrollmentInvoiceController.generateAttachAndEmail(peId, null));
        }
        return results;
    }

    @InvocableMethod(label='Generate & Attach Invoice (No Email)' description='Generates the invoice PDF and attaches it to Program Enrollment; does not email.')
    public static List<Id> generateAndAttach(List<Id> programEnrollmentIds) {
        List<Id> results = new List<Id>();
        if (programEnrollmentIds == null) return results;
        for (Id peId : programEnrollmentIds) {
            if (peId == null) continue;
            results.add(ProgramEnrollmentInvoiceController.generateAndAttach(peId));
        }
        return results;
    }
}