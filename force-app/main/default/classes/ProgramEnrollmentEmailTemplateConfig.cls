/**
 * UCSF Program Enrollment confirmation emails.
 * Implementation Science path uses Lightning EmailTemplate DeveloperName priority list (sandbox suffix variants).
 * Ad Hoc Clinical Research uses DEB-named template DeveloperName DEB_Course_Enrollment_Confirmed when active.
 */
public without sharing class ProgramEnrollmentEmailTemplateConfig {
    private ProgramEnrollmentEmailTemplateConfig() {
    }

    /**
     * Primary preferred developer name when org uses the unsuffixed ucsf-prod style name.
     * See IMPLEMENTATION_STUDENT_CONFIRM_DEVELOPER_NAME_PRIORITY for sandbox fallbacks.
     */
    public static final String STUDENT_CONFIRMATION_DEVELOPER_NAME = 'Program_Enrollment_Confirmation';

    /** Optional Digital Engagement wording for Ad Hoc Clinical Research confirmations. */
    public static final String AD_HOC_DEB_COURSE_ENROLLMENT_CONFIRMED_DEVELOPER_NAME = 'DEB_Course_Enrollment_Confirmed';

    private static final List<String> IMPLEMENTATION_STUDENT_CONFIRM_DEVELOPER_NAME_PRIORITY = new List<String>{
        STUDENT_CONFIRMATION_DEVELOPER_NAME,
        'Program_Enrollment_Confirmation_1752606191568'
    };

    /**
     * UCSF Ad Hoc Clinical Research program Account (prod); align with ProgramEnrollmentOfficeNotify / PaymentReceivedEmailInvocable.
     * Sandboxes may use a different Id — name substring AD HOC CLINICAL RESEARCH is also accepted.
     */
    @TestVisible
    private static Id adHocClinicalResearchProgramAccountId = Id.valueOf('001Dn00000dxeGCIAY');

    private static Map<String, Id> cachedTemplateIdByDeveloperName;
    /** Must be false (not null) — unboxing a null Boolean throws NPE. */
    private static Boolean studentConfirmationTemplateMapsDone = false;

    @TestVisible
    private static void resetStudentConfirmationTemplateCacheForTest() {
        cachedTemplateIdByDeveloperName = null;
        studentConfirmationTemplateMapsDone = false;
    }

    private static void ensureStudentConfirmationMapsLoaded() {
        if (studentConfirmationTemplateMapsDone) {
            return;
        }
        studentConfirmationTemplateMapsDone = true;
        cachedTemplateIdByDeveloperName = new Map<String, Id>();

        Set<String> dns = new Set<String>{ AD_HOC_DEB_COURSE_ENROLLMENT_CONFIRMED_DEVELOPER_NAME };
        dns.addAll(IMPLEMENTATION_STUDENT_CONFIRM_DEVELOPER_NAME_PRIORITY);

        for (EmailTemplate et : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :dns AND IsActive = TRUE
        ]) {
            if (String.isBlank(et.DeveloperName)) {
                continue;
            }
            cachedTemplateIdByDeveloperName.put(et.DeveloperName, et.Id);
        }
    }

    /**
     * True when hed__Program_Enrollment__c is for UCSF Ad Hoc Clinical Research (Account Id matches prod
     * or Account name contains AD HOC CLINICAL RESEARCH).
     */
    public static Boolean isAdHocClinicalResearchProgram(Id programAccountId, String programAccountName) {
        if (programAccountId != null
            && adHocClinicalResearchProgramAccountId != null
            && programAccountId == adHocClinicalResearchProgramAccountId) {
            return true;
        }
        if (programAccountName == null) {
            return false;
        }
        return programAccountName.toUpperCase().contains('AD HOC CLINICAL RESEARCH');
    }

    /** Active DEB / Ad Hoc confirmation template Id, or null when missing/inactive in the org. */
    public static Id getActiveAdHocDebStudentConfirmationTemplateId() {
        ensureStudentConfirmationMapsLoaded();
        return cachedTemplateIdByDeveloperName != null
            ? cachedTemplateIdByDeveloperName.get(AD_HOC_DEB_COURSE_ENROLLMENT_CONFIRMED_DEVELOPER_NAME)
            : null;
    }

    /**
     * Legacy entry: Implementation Science confirmation template matching first available DeveloperName
     * in IMPLEMENTATION_STUDENT_CONFIRM_DEVELOPER_NAME_PRIORITY; null when none deployed.
     */
    public static Id getActiveStudentConfirmationTemplateId() {
        ensureStudentConfirmationMapsLoaded();
        if (cachedTemplateIdByDeveloperName == null || cachedTemplateIdByDeveloperName.isEmpty()) {
            return null;
        }
        for (String dn : IMPLEMENTATION_STUDENT_CONFIRM_DEVELOPER_NAME_PRIORITY) {
            Id tId = cachedTemplateIdByDeveloperName.get(dn);
            if (tId != null) {
                return tId;
            }
        }
        return null;
    }

    /**
     * Resolves Lightning EmailTemplate Id for the Program Enrollment confirmation send path.
     * Ad Hoc → DEB template when deployed; otherwise Implementation Science variant.
     */
    public static Id resolveStudentConfirmationTemplateId(Id programAccountId, String programAccountName) {
        if (isAdHocClinicalResearchProgram(programAccountId, programAccountName)) {
            Id deb = getActiveAdHocDebStudentConfirmationTemplateId();
            return deb != null ? deb : getActiveStudentConfirmationTemplateId();
        }
        return getActiveStudentConfirmationTemplateId();
    }

    /**
     * All active template Ids used by this config (for EmailMessage duplicate detection across variants).
     */
    public static Set<Id> allActiveStudentConfirmationTemplateIds() {
        ensureStudentConfirmationMapsLoaded();
        Set<Id> out = new Set<Id>();
        if (cachedTemplateIdByDeveloperName != null && !cachedTemplateIdByDeveloperName.isEmpty()) {
            out.addAll(cachedTemplateIdByDeveloperName.values());
        }
        return out;
    }
}
