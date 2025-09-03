public with sharing class PEInvoiceFlowActions {
    public class Request {
        @InvocableVariable(required=true) public Id programEnrollmentId;
        @InvocableVariable public List<String> toAddresses;
    }
    public class Response { @InvocableVariable public Id contentVersionId; }

    @InvocableMethod(label='Generate & Email Invoice (Program Enrollment)', description='Renders PDF for hed__Program_Enrollment__c, attaches it to the record, and emails the student + optional recipients.')
    public static List<Response> generateAndEmail(List<Request> requests) {
        List<Response> outList = new List<Response>();
        for (Request r : requests) {
            Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(r.programEnrollmentId, r.toAddresses);
            Response resp = new Response();
            resp.contentVersionId = cvId;
            outList.add(resp);
        }
        return outList;
    }
}