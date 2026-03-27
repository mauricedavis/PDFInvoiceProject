/**
 * without sharing: readiness checks query Contact Files; same visibility issue as ProgramEnrollmentStudentEmail.
 */
public without sharing class ProgramEnrollmentStudentEmailQueueable implements Queueable {

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

        // FormAssembly may attach the responses PDF after invoice batch; allow many queueable hops.
        Integer maxRetries = 40;

        // Determine readiness: invoice PDF on PE and responses PDF on Contact and/or non-invoice PDF on PE.
        // In tests, we still evaluate readiness for coverage/behavior, but we never chain a new async job.
        Boolean allReady = true;
        for (Id peId : peIds) {
            if (!ProgramEnrollmentStudentEmail.hasInvoicePdf(peId)) {
                allReady = false;
                break;
            }

            Id contactId = ProgramEnrollmentStudentEmail.getContactId(peId);
            // Responses may exist only on the PE (FormAssembly); do not require Contact for readiness.
            if (!ProgramEnrollmentStudentEmail.hasResponsesSourceForStudentEmail(peId, contactId)) {
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

