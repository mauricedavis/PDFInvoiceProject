/**
 * UCSF Program Enrollment confirmation emails: single Template Unique Name (DeveloperName) for prod-aligned orgs.
 * If ucsf-prod renames the template, update STUDENT_CONFIRMATION_DEVELOPER_NAME only here.
 */
public without sharing class ProgramEnrollmentEmailTemplateConfig {
    private ProgramEnrollmentEmailTemplateConfig() {
    }

    /** Setup → Email Templates → Template Unique Name (Classic or Lightning). */
    public static final String STUDENT_CONFIRMATION_DEVELOPER_NAME = 'Program_Enrollment_Confirmation';

    private static Id cachedStudentConfirmationTemplateId;
    /** Must be false (not null) — unboxing a null Boolean throws NPE. */
    private static Boolean studentConfirmationTemplateLookupDone = false;

    @TestVisible
    private static void resetStudentConfirmationTemplateCacheForTest() {
        cachedStudentConfirmationTemplateId = null;
        studentConfirmationTemplateLookupDone = false;
    }

    /**
     * Active EmailTemplate Id for merge/render, or null if missing or inactive (callers use inline fallback).
     */
    public static Id getActiveStudentConfirmationTemplateId() {
        if (studentConfirmationTemplateLookupDone) {
            return cachedStudentConfirmationTemplateId;
        }
        studentConfirmationTemplateLookupDone = true;
        List<EmailTemplate> rows = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :STUDENT_CONFIRMATION_DEVELOPER_NAME
              AND IsActive = TRUE
            LIMIT 1
        ];
        cachedStudentConfirmationTemplateId = rows.isEmpty() ? null : rows[0].Id;
        return cachedStudentConfirmationTemplateId;
    }
}
