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

            // Always enqueue student confirmation even if generateAttachAndEmail throws (e.g. lock/contention).
            try {
                ProgramEnrollmentInvoiceController.generateAttachAndEmail(
                    r.ProgramEnrollmentId,
                    r.CcAddresses
                );
            } finally {
                ProgramEnrollmentInvoiceController.enqueueStudentConfirmationAfterInvoice(r.ProgramEnrollmentId);
            }

            outIds.add(r.ProgramEnrollmentId);
        }
        return outIds;
    }
}