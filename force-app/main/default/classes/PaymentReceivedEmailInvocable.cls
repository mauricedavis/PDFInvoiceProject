/**
 * Sends the Implementation Science "payment received" confirmation as real HTML email.
 * Flow's emailSimple action does not support richTextEmailBody in all orgs/API mixes; Apex setHtmlBody is reliable.
 *
 * Enrollment wording uses the student's Course Connection row: Course Offering name when available, else
 * Course_Name__c, else the connection Name — falling back to the program Account name if no connection exists.
 */
public without sharing class PaymentReceivedEmailInvocable {

    private static final String PROGRAM_OFFICE_FROM_EMAIL = 'implementationscience@ucsf.edu';
    private static final String SUBJECT = 'Thank you \u2014 we received your payment';

    private static Id cachedProgramOfficeOweaId;
    private static Boolean programOfficeOweaLookupDone = false;

    /** Set during sendPaymentConfirmation; used in tests instead of calling Messaging.sendEmail (OWEA/domain rules). */
    @TestVisible
    private static Integer lastBuiltEmailCountForTest = 0;

    /** Last HTML body built in test context (sendEmail is not invoked in tests). */
    @TestVisible
    private static String lastHtmlBodyForTest;

    public class Request {
        @InvocableVariable(required=true)
        public Id opportunityId;

        @InvocableVariable(required=true)
        public Id programEnrollmentId;
    }

    @InvocableMethod(
        label='Send payment received confirmation (HTML)'
        description='Sends HTML payment confirmation from the Program Office OWEA when the program Account name contains IMPLEMENTATION SCIENCE and the student has an email.'
    )
    public static void sendPaymentConfirmation(List<Request> requests) {
        lastBuiltEmailCountForTest = 0;
        lastHtmlBodyForTest = null;

        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> peIds = new Set<Id>();
        for (Request r : requests) {
            if (r != null && r.programEnrollmentId != null) {
                peIds.add(r.programEnrollmentId);
            }
        }
        if (peIds.isEmpty()) {
            return;
        }

        Map<Id, hed__Program_Enrollment__c> peMap = new Map<Id, hed__Program_Enrollment__c>(
            [
                SELECT
                    Id,
                    hed__Contact__c,
                    hed__Contact__r.FirstName,
                    hed__Contact__r.Email,
                    hed__Account__r.Name
                FROM hed__Program_Enrollment__c
                WHERE Id IN :peIds
            ]
        );

        Map<Id, String> offeringLabelByPeId = resolveCourseOfferingLabels(peIds);

        List<Messaging.SingleEmailMessage> toSend = new List<Messaging.SingleEmailMessage>();
        Id oweaId = getProgramOfficeOrgWideEmailAddressId();

        for (Request r : requests) {
            if (r == null || r.opportunityId == null || r.programEnrollmentId == null) {
                continue;
            }
            hed__Program_Enrollment__c pe = peMap.get(r.programEnrollmentId);
            if (pe == null || pe.hed__Contact__c == null || String.isBlank(pe.hed__Contact__r.Email)) {
                continue;
            }
            String acctName = (pe.hed__Account__r != null && pe.hed__Account__r.Name != null)
                ? pe.hed__Account__r.Name
                : '';
            if (!acctName.toUpperCase().contains('IMPLEMENTATION SCIENCE')) {
                continue;
            }

            String firstName = String.isNotBlank(pe.hed__Contact__r.FirstName)
                ? pe.hed__Contact__r.FirstName
                : 'there';

            String enrolledLabel = offeringLabelByPeId.get(pe.Id);
            if (String.isBlank(enrolledLabel)) {
                enrolledLabel = String.isNotBlank(acctName) ? acctName : 'your program';
            }

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTargetObjectId(pe.hed__Contact__c);
            msg.setWhatId(r.opportunityId);
            msg.setTreatTargetObjectAsRecipient(true);
            msg.setSaveAsActivity(true);
            msg.setSubject(SUBJECT);
            String html = buildHtmlBody(htmlEsc(firstName), htmlEsc(enrolledLabel));
            msg.setHtmlBody(html);
            if (Test.isRunningTest()) {
                lastHtmlBodyForTest = html;
            }
            if (oweaId != null) {
                msg.setOrgWideEmailAddressId(oweaId);
            }
            toSend.add(msg);
        }

        if (toSend.isEmpty()) {
            return;
        }

        lastBuiltEmailCountForTest = toSend.size();

        if (Test.isRunningTest()) {
            return;
        }

        try {
            Messaging.sendEmail(toSend);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'PaymentReceivedEmailInvocable: sendEmail failed: ' +
                    e.getTypeName() +
                    ' - ' +
                    e.getMessage()
            );
        }
    }

    /**
     * One display label per Program Enrollment: earliest Course_Offering_Start_Date__c when that field exists,
     * otherwise the first matching Course Connection in iteration order.
     */
    private static Map<Id, String> resolveCourseOfferingLabels(Set<Id> programEnrollmentIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (programEnrollmentIds == null || programEnrollmentIds.isEmpty()) {
            return result;
        }

        Map<String, Schema.SObjectField> ceFields = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        String whereIn = courseConnectionWhereProgramEnrollmentsIn(ceFields);
        if (String.isBlank(whereIn)) {
            return result;
        }

        List<String> selectParts = new List<String>{
            'Id',
            'Name',
            'Term_Enrollment__c',
            'Term_Enrollment__r.Program_Enrollment__c'
        };
        if (ceFields.containsKey('Program_Enrollment__c')) {
            selectParts.add('Program_Enrollment__c');
        }
        if (ceFields.containsKey('hed__Program_Enrollment__c')) {
            selectParts.add('hed__Program_Enrollment__c');
        }
        if (ceFields.containsKey('Course_Name__c')) {
            selectParts.add('Course_Name__c');
        }
        if (ceFields.containsKey('hed__Course_Offering__c')) {
            selectParts.add('hed__Course_Offering__r.Name');
        }
        if (ceFields.containsKey('Course_Offering_Start_Date__c')) {
            selectParts.add('Course_Offering_Start_Date__c');
        }

        String soql =
            'SELECT ' +
            String.join(selectParts, ', ') +
            ' FROM hed__Course_Enrollment__c WHERE ' +
            whereIn;

        List<hed__Course_Enrollment__c> rows = (List<hed__Course_Enrollment__c>) Database.query(soql);
        return offeringLabelsFromCourseConnectionRows(rows, programEnrollmentIds, ceFields);
    }

    /**
     * Test hook: build labels from in-memory rows (e.g. JSON) without DML — covers offering / date / lookup branches.
     */
    @TestVisible
    private static Map<Id, String> offeringLabelsFromCourseConnectionRowsForTest(
        List<hed__Course_Enrollment__c> rows,
        Set<Id> programEnrollmentIds
    ) {
        return offeringLabelsFromCourseConnectionRows(
            rows,
            programEnrollmentIds,
            Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap()
        );
    }

    private static Map<Id, String> offeringLabelsFromCourseConnectionRows(
        List<hed__Course_Enrollment__c> rows,
        Set<Id> programEnrollmentIds,
        Map<String, Schema.SObjectField> ceFields
    ) {
        Map<Id, String> result = new Map<Id, String>();
        if (rows == null || rows.isEmpty() || programEnrollmentIds == null || programEnrollmentIds.isEmpty()) {
            return result;
        }

        Map<Id, hed__Course_Enrollment__c> bestByPe = new Map<Id, hed__Course_Enrollment__c>();
        for (hed__Course_Enrollment__c cc : rows) {
            Id peId = courseConnectionProgramEnrollmentId(cc, ceFields);
            if (peId == null || !programEnrollmentIds.contains(peId)) {
                continue;
            }
            if (!bestByPe.containsKey(peId)) {
                bestByPe.put(peId, cc);
                continue;
            }
            if (shouldPreferCourseConnection(cc, bestByPe.get(peId), ceFields)) {
                bestByPe.put(peId, cc);
            }
        }

        for (Id peId : bestByPe.keySet()) {
            result.put(peId, offeringDisplayName(bestByPe.get(peId), ceFields));
        }
        return result;
    }

    /** Same relationship paths as ProgramEnrollmentInvoiceController.courseConnectionWhereClauseForProgramEnrollment, with IN :programEnrollmentIds. */
    private static String courseConnectionWhereProgramEnrollmentsIn(Map<String, Schema.SObjectField> ceFields) {
        List<String> ors = new List<String>{ 'Term_Enrollment__r.Program_Enrollment__c IN :programEnrollmentIds' };
        if (ceFields.containsKey('hed__Program_Enrollment__c')) {
            ors.add('hed__Program_Enrollment__c IN :programEnrollmentIds');
        }
        if (ceFields.containsKey('Program_Enrollment__c')) {
            ors.add('Program_Enrollment__c IN :programEnrollmentIds');
        }
        return '(' + String.join(ors, ' OR ') + ')';
    }

    private static Id courseConnectionProgramEnrollmentId(
        hed__Course_Enrollment__c cc,
        Map<String, Schema.SObjectField> ceFields
    ) {
        if (ceFields.containsKey('Program_Enrollment__c') && cc.get('Program_Enrollment__c') != null) {
            return (Id) cc.get('Program_Enrollment__c');
        }
        if (ceFields.containsKey('hed__Program_Enrollment__c') && cc.get('hed__Program_Enrollment__c') != null) {
            return (Id) cc.get('hed__Program_Enrollment__c');
        }
        if (cc.Term_Enrollment__r != null && cc.Term_Enrollment__r.Program_Enrollment__c != null) {
            return cc.Term_Enrollment__r.Program_Enrollment__c;
        }
        return null;
    }

    private static Boolean shouldPreferCourseConnection(
        hed__Course_Enrollment__c candidate,
        hed__Course_Enrollment__c current,
        Map<String, Schema.SObjectField> ceFields
    ) {
        if (!ceFields.containsKey('Course_Offering_Start_Date__c')) {
            return false;
        }
        Date dNew = (Date) candidate.get('Course_Offering_Start_Date__c');
        Date dOld = (Date) current.get('Course_Offering_Start_Date__c');
        if (dNew == null && dOld == null) {
            return false;
        }
        if (dOld == null) {
            return true;
        }
        if (dNew == null) {
            return false;
        }
        return dNew < dOld;
    }

    private static String offeringDisplayName(
        hed__Course_Enrollment__c cc,
        Map<String, Schema.SObjectField> ceFields
    ) {
        if (ceFields.containsKey('hed__Course_Offering__c')) {
            SObject co = cc.getSObject('hed__Course_Offering__r');
            if (co != null) {
                String n = (String) co.get('Name');
                if (String.isNotBlank(n)) {
                    return n;
                }
            }
        }
        if (ceFields.containsKey('Course_Name__c')) {
            String cn = (String) cc.get('Course_Name__c');
            if (String.isNotBlank(cn)) {
                return cn;
            }
        }
        return cc.Name != null ? cc.Name : '';
    }

    private static Id getProgramOfficeOrgWideEmailAddressId() {
        if (programOfficeOweaLookupDone) {
            return cachedProgramOfficeOweaId;
        }
        programOfficeOweaLookupDone = true;
        for (OrgWideEmailAddress o : [SELECT Id, Address FROM OrgWideEmailAddress]) {
            if (o.Address != null && o.Address.trim().equalsIgnoreCase(PROGRAM_OFFICE_FROM_EMAIL)) {
                cachedProgramOfficeOweaId = o.Id;
                break;
            }
        }
        return cachedProgramOfficeOweaId;
    }

    private static String htmlEsc(String s) {
        if (s == null) {
            return '';
        }
        return s.replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }

    private static String buildHtmlBody(String firstNameEscaped, String enrolledInEscaped) {
        return '<div style="font-family: Segoe UI, Arial, sans-serif; font-size: 14px; color: #333333; line-height: 1.5; max-width: 560px;">'
            + '<p style="margin: 0 0 12px 0;">Hello '
            + firstNameEscaped
            + ',</p>'
            + '<p style="margin: 0 0 12px 0;">Thank you, we received your payment. You are enrolled in <strong>'
            + enrolledInEscaped
            + '</strong>.</p>'
            + '<p style="margin: 0 0 12px 0;">Course dates and enrollment policies can be found through the <a href="https://epibiostat.ucsf.edu/online-certificate-implementation-science">UCSF Implementation Science Training Program&#39;s main page</a>.</p>'
            + '<p style="margin: 0 0 12px 0;">If you wish to change this enrollment, please reach out to us as soon as possible at <a href="mailto:ImplementationScience@ucsf.edu">ImplementationScience@ucsf.edu</a>.</p>'
            + '<p style="margin: 0 0 12px 0;">Thank you. We look forward to working with you.</p>'
            + '<p style="margin: 16px 0 0 0; color: #555555;">&mdash; The UCSF Implementation Science Team</p>'
            + '</div>';
    }
}
