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

            // Perform the side effect (generate, attach, and email invoice)
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(
                r.ProgramEnrollmentId,
                r.CcAddresses
            );

            // Return the PE Id to the Flow as a simple acknowledgment
            outIds.add(r.ProgramEnrollmentId);
        }
        return outIds;
    }
}