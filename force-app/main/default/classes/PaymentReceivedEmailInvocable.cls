/**
 * Sends the Implementation Science "payment received" confirmation as real HTML email.
 * Flow's emailSimple action does not support richTextEmailBody in all orgs/API mixes; Apex setHtmlBody is reliable.
 *
 * Logo: img src uses the org-domain /resource/... URL for public-cache static resource ImplemenationScienceLogo so
 * clients like Gmail render inline without CID attachments. Override with Custom Label
 * For a logo hosted outside Salesforce (e.g. program site CDN), add Custom Metadata or a similar config later;
 * vf.force.com Visualforce host URLs often require login and are not suitable as the img src for external recipients.
 */
public without sharing class PaymentReceivedEmailInvocable {

    private static final String PROGRAM_OFFICE_FROM_EMAIL = 'implementationscience@ucsf.edu';
    private static final String SUBJECT = 'Thank you \u2014 we received your payment';
    /** Fallback when label is blank and static resource URL cannot be resolved (tests, misnamed SR, etc.). */
    private static final String LOGO_FALLBACK_URL = 'https://www.ucsf.edu/themes/custom/ucsf/logo.svg';
    /** Org static resource name (matches existing UCSF asset spelling). */
    private static final String LOGO_STATIC_RESOURCE_NAME = 'ImplemenationScienceLogo';

    private static Id cachedProgramOfficeOweaId;
    private static Boolean programOfficeOweaLookupDone = false;

    /** Set during sendPaymentConfirmation; used in tests instead of calling Messaging.sendEmail (OWEA/domain rules). */
    @TestVisible
    private static Integer lastBuiltEmailCountForTest = 0;

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

        List<Messaging.SingleEmailMessage> toSend = new List<Messaging.SingleEmailMessage>();
        Id oweaId = getProgramOfficeOrgWideEmailAddressId();
        String logoImgSrc = resolveLogoImgSrc();

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
            String programName = String.isNotBlank(acctName) ? acctName : 'your program';

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTargetObjectId(pe.hed__Contact__c);
            msg.setWhatId(r.opportunityId);
            msg.setTreatTargetObjectAsRecipient(true);
            msg.setSaveAsActivity(true);
            msg.setSubject(SUBJECT);
            msg.setHtmlBody(buildHtmlBody(htmlEsc(firstName), htmlEsc(programName), logoImgSrc));
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

    private static Id getProgramOfficeOrgWideEmailAddressId() {
        if (Test.isRunningTest()) {
            return null;
        }
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

    /** Absolute URL to public-cache static resource on the org domain (no CID attachments). */
    private static String resolveLogoImgSrc() {
        String fromResource = absoluteUrlForStaticResource(LOGO_STATIC_RESOURCE_NAME);
        if (String.isNotBlank(fromResource)) {
            return htmlEscAttr(fromResource);
        }
        return LOGO_FALLBACK_URL;
    }

    private static String absoluteUrlForStaticResource(String resourceName) {
        if (String.isBlank(resourceName)) {
            return null;
        }
        try {
            PageReference pr = PageReference.forResource(resourceName);
            if (pr == null) {
                return null;
            }
            String path = pr.getUrl();
            if (String.isBlank(path)) {
                return null;
            }
            return URL.getOrgDomainUrl().toExternalForm() + path;
        } catch (Exception e) {
            return null;
        }
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

    private static String htmlEscAttr(String s) {
        if (s == null) {
            return '';
        }
        return s.replace('&', '&amp;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    private static String buildHtmlBody(
        String firstNameEscaped,
        String programNameEscaped,
        String logoImgSrc
    ) {
        return '<div style="font-family: Segoe UI, Arial, sans-serif; font-size: 14px; color: #333333; line-height: 1.5; max-width: 560px;">'
            + '<p style="margin: 0 0 16px 0;"><img src="'
            + logoImgSrc
            + '" width="280" alt="UCSF Implementation Science" style="border: 0; display: block; max-width: 100%; height: auto;" /></p>'
            + '<p style="margin: 0 0 12px 0;">Hello '
            + firstNameEscaped
            + ',</p>'
            + '<p style="margin: 0 0 12px 0;">Thank you, we received your payment. You are enrolled in <strong>'
            + programNameEscaped
            + '</strong>.</p>'
            + '<p style="margin: 0 0 12px 0;">Course dates and enrollment policies can be found through the <a href="https://implementationscience.ucsf.edu/">UCSF Implementation Science Training Program&#39;s main page</a>.</p>'
            + '<p style="margin: 0 0 12px 0;">If you wish to change this enrollment, please reach out to us as soon as possible at <a href="mailto:ImplementationScience@ucsf.edu">ImplementationScience@ucsf.edu</a>.</p>'
            + '<p style="margin: 0 0 12px 0;">Thank you. We look forward to working with you.</p>'
            + '<p style="margin: 16px 0 0 0; color: #555555;">&mdash; The UCSF Implementation Science Team</p>'
            + '</div>';
    }
}
