public with sharing class ProgramEnrollmentInvoiceFlowAction {

    @InvocableMethod(
        label='Generate and Attach Program Enrollment Invoice PDF'
        description='Generates the Program Enrollment Invoice PDF, attaches it to the record, and emails it to the student.'
    )
    public static void generateInvoice(List<Id> enrollmentIds) {
        if (enrollmentIds == null || enrollmentIds.isEmpty()) return;

        for (Id peId : enrollmentIds) {
            System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(new List<Id>{ peId }));
        }
    }
}