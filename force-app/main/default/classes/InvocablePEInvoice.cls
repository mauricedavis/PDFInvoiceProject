public with sharing class InvocablePEInvoice {
    public class Request {
        @InvocableVariable(required=true) public Id programEnrollmentId;
        @InvocableVariable public List<String> toAddresses;
    }
    public class Response { @InvocableVariable public Id contentVersionId; }

    @InvocableMethod(label='Generate & Email Invoice (Program Enrollment)', description='Render invoice PDF for Program Enrollment, attach, and email student (+ optional recipients).')
    public static List<Response> generateAndEmail(List<Request> requests) {
        List<Response> outList = new List<Response>();
        for (Request r : requests) {
            Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(
                r.programEnrollmentId, r.toAddresses
            );
            Response resp = new Response();
            resp.contentVersionId = cvId;
            outList.add(resp);
        }
        return outList;
    }
}
