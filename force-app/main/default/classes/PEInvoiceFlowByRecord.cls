public with sharing class PEInvoiceFlowByRecord {
    public class Req {
        @InvocableVariable(required=true)
        public Id ProgramEnrollmentId;
        @InvocableVariable(required=false)
        public List<String> CcAddresses;
    }

    @InvocableMethod(label='Generate, Attach & Email Invoice (by Record)'
                     description='Generates the invoice PDF, attaches to Program Enrollment, emails the student, logs Task + EmailMessage, and updates flags.')
    public static List<Id> generateAndEmail(List<Req> reqs) {
        List<Id> result = new List<Id>();
        if (reqs == null) return result;
        for (Req r : reqs) {
            if (r == null || r.ProgramEnrollmentId == null) continue;
            result.add(ProgramEnrollmentInvoiceController.generateAttachAndEmail(r.ProgramEnrollmentId, r.CcAddresses));
        }
        return result;
    }
}