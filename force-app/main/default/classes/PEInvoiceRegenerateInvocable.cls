/**
 * Run from Flow / Quick Action: regenerates invoice PDF on the Program Enrollment (async batch).
 * Does not send student or Program Office emails.
 */
public with sharing class PEInvoiceRegenerateInvocable {

    public class Request {
        @InvocableVariable(label='Program Enrollment Id' required=true)
        public Id programEnrollmentId;
    }

    @InvocableMethod(
        label='Regenerate Program Enrollment Invoice PDF'
        description='Deletes the existing Invoice_* PDF on the Program Enrollment and generates a new one using the current Visualforce template. Runs asynchronously.'
    )
    public static void regenerate(List<Request> requests) {
        if (requests == null || requests.isEmpty()) return;

        Set<Id> peIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.programEnrollmentId != null) {
                peIds.add(r.programEnrollmentId);
            }
        }
        if (peIds.isEmpty()) return;

        if (Test.isRunningTest()) {
            for (Id peId : peIds) {
                ProgramEnrollmentInvoiceController.regenerateInvoicePdf(peId);
            }
            return;
        }

        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(new List<Id>(peIds)), 1);
    }
}
