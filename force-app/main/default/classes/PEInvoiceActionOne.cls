public with sharing class PEInvoiceActionOne {
    public class Req {
        @InvocableVariable(required=true) public Id ProgramEnrollmentId;
        @InvocableVariable public List<String> CcAddresses;
    }
    @InvocableMethod(label='Send Program Enrollment Invoice (Attach + Email + Log + Update)')
    public static List<Id> send(List<Req> reqs) {
        List<Id> outIds = new List<Id>();
        if (reqs == null) return outIds;

        for (Req r : reqs) {
            if (r == null || r.ProgramEnrollmentId == null) continue;

            // Student confirmation is chained from ProgramEnrollmentInvoiceBatch.finish (or invoice queueable
            // when invoice already exists) after the invoice PDF is attachable — not here.
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(
                r.ProgramEnrollmentId,
                r.CcAddresses
            );

            outIds.add(r.ProgramEnrollmentId);
        }
        return outIds;
    }
}
