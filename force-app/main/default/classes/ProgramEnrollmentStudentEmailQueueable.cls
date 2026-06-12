/**
 * without sharing: readiness checks query Contact Files; same visibility issue as ProgramEnrollmentStudentEmail.
 */
public without sharing class ProgramEnrollmentStudentEmailQueueable implements Queueable {

    /** Must match Payment Processing flow (Program Enrollment update). */
    private static final String ENROLLMENT_STATUS_CURRENTLY_ENROLLED = 'Currently Enrolled';

    private final List<Id> peIds;
    private final Integer retry;
    private final Boolean forceResend;

    public ProgramEnrollmentStudentEmailQueueable(List<Id> peIds) {
        this(peIds, 0, false);
    }

    public ProgramEnrollmentStudentEmailQueueable(List<Id> peIds, Boolean forceResend) {
        this(peIds, 0, forceResend == true);
    }

    @TestVisible
    private ProgramEnrollmentStudentEmailQueueable(List<Id> peIds, Integer retry) {
        this(peIds, retry, false);
    }

    @TestVisible
    private ProgramEnrollmentStudentEmailQueueable(List<Id> peIds, Integer retry, Boolean forceResend) {
        this.peIds = (peIds == null) ? new List<Id>() : new List<Id>(peIds);
        this.retry = retry;
        this.forceResend = forceResend == true;
    }

    public void execute(QueueableContext context) {
        if (peIds.isEmpty()) return;

        Map<Id, hed__Program_Enrollment__c> peById = new Map<Id, hed__Program_Enrollment__c>(
            [
                SELECT Id,
                       hed__Enrollment_Status__c,
                       hed__Account__c,
                       hed__Account__r.Name
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

        Boolean allReady = true;
        for (Id peId : workPeIds) {
            if (!ProgramEnrollmentStudentEmail.isStudentConfirmationAttachmentsReady(peId)) {
                allReady = false;
                break;
            }

            hed__Program_Enrollment__c peRow = peById.get(peId);
            String acctNm =
                peRow != null && peRow.hed__Account__r != null
                    ? peRow.hed__Account__r.Name
                    : null;
            Id confirmationTemplateId =
                peRow != null
                    ? ProgramEnrollmentEmailTemplateConfig.resolveStudentConfirmationTemplateId(
                          peRow.hed__Account__c,
                          acctNm
                      )
                    : null;
            if (confirmationTemplateId != null
                && ProgramEnrollmentEmailTemplateConfig.isAdHocClinicalResearchProgram(
                    peRow.hed__Account__c,
                    acctNm
                )
                && !ProgramEnrollmentStudentEmail.isConfirmationTermReady(peId)) {
                allReady = false;
                break;
            }
        }

        if (!allReady) {
            if (!Test.isRunningTest() && retry < maxRetries) {
                System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(workPeIds, retry + 1, forceResend));
            } else if (!Test.isRunningTest() && retry >= maxRetries) {
                ProgramEnrollmentStudentEmail.logReadinessTimeoutTasks(workPeIds);
            }
            return;
        }

        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(workPeIds, forceResend);
    }
}
