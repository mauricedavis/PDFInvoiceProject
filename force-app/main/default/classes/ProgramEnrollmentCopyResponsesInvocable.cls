/**
 * Separate class because Salesforce allows only one @InvocableMethod per Apex class
 * (ProgramEnrollmentStudentEmail already exposes Send Student Confirmation Email).
 */
public without sharing class ProgramEnrollmentCopyResponsesInvocable {

    public class ProgramEnrollmentRequest {
        @InvocableVariable(required=true)
        public Id programEnrollmentId;
    }

    @InvocableMethod(
        label='Copy FA responses PDF from Contact to Program Enrollment'
        description='Links the latest FA responses PDF from the Contact to the Program Enrollment when needed. Does not send email.'
    )
    public static void copyResponsesPdfToProgramEnrollment(List<ProgramEnrollmentRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        for (ProgramEnrollmentRequest r : requests) {
            if (r != null && r.programEnrollmentId != null) {
                ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(r.programEnrollmentId);
            }
        }
    }
}
