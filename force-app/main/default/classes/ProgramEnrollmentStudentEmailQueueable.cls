public with sharing class ProgramEnrollmentStudentEmailQueueable implements Queueable {

    private final List<Id> peIds;
    private final Integer retry;

    public ProgramEnrollmentStudentEmailQueueable(List<Id> peIds) {
        this(peIds, 0);
    }

    @TestVisible
    private ProgramEnrollmentStudentEmailQueueable(List<Id> peIds, Integer retry) {
        this.peIds = (peIds == null) ? new List<Id>() : new List<Id>(peIds);
        this.retry = retry;
    }

    public void execute(QueueableContext context) {
        if (peIds.isEmpty()) return;

        // FormAssembly + invoice batch can take several async hops; keep this comfortably above typical delay.
        Integer maxRetries = 15;

        // Determine readiness: invoice PDF exists on each PE and Contact has at least one PDF response.
        // In tests, we still evaluate readiness for coverage/behavior, but we never chain a new async job.
        Boolean allReady = true;
        for (Id peId : peIds) {
            if (!ProgramEnrollmentStudentEmail.hasInvoicePdf(peId)) {
                allReady = false;
                break;
            }

            Id contactId = ProgramEnrollmentStudentEmail.getContactId(peId);
            if (contactId == null || !ProgramEnrollmentStudentEmail.hasAnyResponsesPdf(contactId)) {
                allReady = false;
                break;
            }
        }

        if (!allReady) {
            // Not ready: retry up to maxRetries, then stop (do NOT attempt to send or publish files).
            if (!Test.isRunningTest() && retry < maxRetries) {
                System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(peIds, retry + 1));
            } else if (!Test.isRunningTest() && retry >= maxRetries) {
                ProgramEnrollmentStudentEmail.logReadinessTimeoutTasks(peIds);
            }
            return;
        }

        // Ready: send the email(s).
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(peIds);
    }
}

