/**
 * without sharing: readiness checks query Contact Files; same visibility issue as ProgramEnrollmentStudentEmail.
 */
public without sharing class ProgramEnrollmentStudentEmailQueueable implements Queueable {

    /** Must match Payment Processing flow (Program Enrollment update). */
    private static final String ENROLLMENT_STATUS_CURRENTLY_ENROLLED = 'Currently Enrolled';

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

        Map<Id, hed__Program_Enrollment__c> peById = new Map<Id, hed__Program_Enrollment__c>(
            [
                SELECT Id, hed__Enrollment_Status__c
                FROM hed__Program_Enrollment__c
                WHERE Id IN :peIds
            ]
        );
        List<Id> workPeIds = new List<Id>();
        for (Id peId : peIds) {
            hed__Program_Enrollment__c peRow = peById.get(peId);
            if (peRow == null) {
                continue;
            }
            if (!ENROLLMENT_STATUS_CURRENTLY_ENROLLED.equals(peRow.hed__Enrollment_Status__c)) {
                workPeIds.add(peId);
            }
        }
        if (workPeIds.isEmpty()) {
            return;
        }

        // FormAssembly may attach the responses PDF after invoice batch; allow many queueable hops.
        Integer maxRetries = 40;

        // Determine readiness: invoice PDF on PE and responses PDF on Contact and/or non-invoice PDF on PE.
        // In tests, we still evaluate readiness for coverage/behavior, but we never chain a new async job.
        Boolean allReady = true;
        for (Id peId : workPeIds) {
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
                System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(workPeIds, retry + 1));
            } else if (!Test.isRunningTest() && retry >= maxRetries) {
                ProgramEnrollmentStudentEmail.logReadinessTimeoutTasks(workPeIds);
            }
            return;
        }

        // Ready: send the email(s).
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(workPeIds);
    }
}

