public with sharing class InvocablePEInvoice {
    public class Request {
        @InvocableVariable(required=true) public Id programEnrollmentId;
        @InvocableVariable public List<String> toAddresses;
    }
    public class Response { @InvocableVariable public Id contentVersionId; }

    @InvocableMethod
    public static List<Response> generateAndEmail(List<Request> requests) {
        List<Response> outList = new List<Response>();
        for (Request r : requests) {
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(
                r.programEnrollmentId, r.toAddresses
            );
            Response resp = new Response();
            resp.contentVersionId = null; // Controller does not return ContentVersion Id
            outList.add(resp);
        }
        return outList;
    }
}