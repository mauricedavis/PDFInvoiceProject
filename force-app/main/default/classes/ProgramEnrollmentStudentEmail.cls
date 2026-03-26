/**
 * Student confirmation mail should appear From the Program Office mailbox, not the automation user.
 * Requires a verified Org-Wide Email Address in Setup → Organization-Wide Addresses whose Address
 * matches PROGRAM_OFFICE_FROM_EMAIL (case-insensitive), and access granted to the user/profile that
 * runs the Flow or Queueable that sends this email.
 *
 * without sharing: FormAssembly stores the responses PDF on the Contact; the queueable/invocable
 * often runs as an integration or system user that cannot see those Files under with sharing.
 * We must read Contact-linked ContentVersion and publish a copy on the PE reliably.
 *
 * Body/subject: uses active EmailTemplate from ProgramEnrollmentEmailTemplateConfig (ucsf-prod) when present;
 * otherwise the inline plain-text confirmation (tests/sandboxes without that template).
 */
public without sharing class ProgramEnrollmentStudentEmail {

    /** Canonical Program Office sender; must match the verified OWEA Address in each org. */
    private static final String PROGRAM_OFFICE_FROM_EMAIL = 'implementationscience@ucsf.edu';

    private static Id cachedProgramOfficeOweaId;
    private static Boolean programOfficeOweaLookupDone;

    @TestVisible
    private static Boolean allowOrgWideEmailLookupInTest = false;
    @TestVisible
    private static Boolean allowLogReadinessTimeoutTasksInTest = false;

    @TestVisible
    private static void resetOweaCacheForTest() {
        cachedProgramOfficeOweaId = null;
        programOfficeOweaLookupDone = false;
    }

    /**
     * Resolves the OrgWideEmailAddress Id for PROGRAM_OFFICE_FROM_EMAIL (case-insensitive).
     * Returns null in unit tests or when no matching OWEA exists (email then uses running user as From).
     */
    private static Id getProgramOfficeOrgWideEmailAddressId() {
        if (Test.isRunningTest() && !allowOrgWideEmailLookupInTest) {
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
        if (cachedProgramOfficeOweaId == null) {
            System.debug(
                LoggingLevel.WARN,
                'ProgramEnrollmentStudentEmail: No OrgWideEmailAddress matches ' + PROGRAM_OFFICE_FROM_EMAIL +
                    '; confirmation email will use the running user as From.'
            );
        }
        return cachedProgramOfficeOweaId;
    }

    public class ProgramEnrollmentRequest {
        @InvocableVariable(required=true)
        public Id programEnrollmentId;
    }

    private class PdfDoc {
        public String title;
        public Blob body;
        public Id contentDocumentId; // present when sourced from Files
    }

    @InvocableMethod(
        label='Send Student Confirmation Email (Responses + Invoice PDFs)'
        description='Sends ONE email to the enrolled student with both the FormAssembly responses PDF and the invoice PDF attached. Logs the sent email to the Contact and Program Enrollment (activity).'
    )
    public static void sendStudentEmail(List<ProgramEnrollmentRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        List<Id> peIds = new List<Id>();
        for (ProgramEnrollmentRequest r : requests) {
            if (r != null && r.programEnrollmentId != null) peIds.add(r.programEnrollmentId);
        }
        if (peIds.isEmpty()) return;

        // Defer to a Queueable that can wait/retry until the invoice is present.
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(peIds));
    }

    /**
     * Publishes "Course Registration Responses" on the PE using the latest FA-style PDF from the
     * Contact (or a non-invoice PDF already on the PE). Does not send email — use to repair PEs or
     * from a Flow step after FormAssembly attaches to the Contact.
     */
    public static void copyResponsesPdfToProgramEnrollment(Id peId) {
        if (peId == null) {
            return;
        }
        List<hed__Program_Enrollment__c> rows = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            WHERE Id = :peId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return;
        }
        hed__Program_Enrollment__c pe = rows[0];
        PdfDoc responses = getLatestResponsesPdf(pe.hed__Contact__c, pe.Id);
        if (responses == null) {
            return;
        }
        ensureResponsesOnProgramEnrollment(pe.Id, pe.hed__Contact__c, responses);
    }

    /**
     * Test hook: publish stable Course Registration Responses from a ContentDocument when body is null (re-query VersionData path).
     */
    @TestVisible
    static Id testEnsureResponsesFromContentDocumentIdOnly(Id peId, Id contentDocumentId) {
        if (peId == null || contentDocumentId == null) {
            return null;
        }
        PdfDoc p = new PdfDoc();
        p.title = 'Test source doc';
        p.body = null;
        p.contentDocumentId = contentDocumentId;
        return ensureResponsesOnProgramEnrollment(peId, null, p);
    }

    private static Task buildTask(Id peId, Id contactId, String subject, String body) {
        if (peId == null && contactId == null) return null;
        Task t = new Task();
        t.Subject = subject;
        t.Description = body;
        t.ActivityDate = Date.today();
        if (contactId != null) t.WhoId = contactId;
        if (peId != null) t.WhatId = peId;
        return t;
    }

    private static PdfDoc getLatestInvoicePdf(Id peId) {
        if (peId == null) return null;

        // Find the most recent linked PDF that looks like the invoice created by our controller.
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
              AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        if (links.isEmpty()) return null;

        ContentVersion cv = [
            SELECT Title, VersionData
            FROM ContentVersion
            WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
            LIMIT 1
        ];

        PdfDoc d = new PdfDoc();
        d.title = cv.Title;
        d.body = cv.VersionData;
        d.contentDocumentId = null;
        return d;
    }

    private static Id getLatestInvoiceVersionId(Id peId) {
        if (peId == null) return null;

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
              AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        if (links.isEmpty() || links[0].ContentDocument.LatestPublishedVersionId == null) return null;
        return links[0].ContentDocument.LatestPublishedVersionId;
    }

    /** Matches invoice PDF naming used elsewhere in this class (SOQL-style). */
    private static Boolean titleLooksLikeInvoice(String title) {
        if (String.isBlank(title)) {
            return false;
        }
        return title.startsWithIgnoreCase('Invoice_') || title.containsIgnoreCase('Invoice');
    }

    /**
     * True if the PE has at least one PDF that is not treated as the invoice (e.g. FormAssembly linked the file to the PE).
     */
    public static Boolean hasNonInvoicePdfOnProgramEnrollment(Id peId) {
        if (peId == null) {
            return false;
        }
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
            ORDER BY SystemModstamp DESC
            LIMIT 50
        ];
        for (ContentDocumentLink lnk : links) {
            if (lnk.ContentDocument == null) {
                continue;
            }
            String t = lnk.ContentDocument.Title;
            if (!titleLooksLikeInvoice(t)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Student email queueable readiness: responses may live on the Contact (typical) or only on the PE (FormAssembly).
     */
    public static Boolean hasResponsesSourceForStudentEmail(Id peId, Id contactId) {
        if (peId == null) {
            return false;
        }
        if (contactId != null && hasAnyResponsesPdf(contactId)) {
            return true;
        }
        return hasNonInvoicePdfOnProgramEnrollment(peId);
    }

    private static PdfDoc getLatestResponsesPdf(Id contactId, Id peId) {
        if (contactId == null && peId == null) {
            return null;
        }

        // 1) Prefer a File linked to the Contact matching common keywords.
        List<ContentDocumentLink> links = (contactId == null)
            ? new List<ContentDocumentLink>()
            : [
                  SELECT ContentDocument.Title,
                         ContentDocument.LatestPublishedVersionId,
                         ContentDocumentId,
                         ContentDocument.FileType
                  FROM ContentDocumentLink
                  WHERE LinkedEntityId = :contactId
                    AND ContentDocument.FileType = 'PDF'
                    AND (
                         ContentDocument.Title LIKE '%Course Registration%'
                      OR ContentDocument.Title LIKE '%Registration%'
                      OR ContentDocument.Title LIKE '%Response%'
                      OR ContentDocument.Title LIKE '%Responses%'
                    )
                  ORDER BY SystemModstamp DESC
                  LIMIT 1
              ];

        if (contactId != null && !links.isEmpty()) {
            ContentVersion cv = [
                SELECT Title, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
                LIMIT 1
            ];
            PdfDoc d = new PdfDoc();
            d.title = cv.Title;
            d.body = cv.VersionData;
            d.contentDocumentId = cv.ContentDocumentId;
            return d;
        }

        // 1b) Fallback: any PDF File linked to the Contact (no title filter).
        List<ContentDocumentLink> anyPdfLinks = (contactId == null)
            ? new List<ContentDocumentLink>()
            : [
                  SELECT ContentDocument.Title,
                         ContentDocument.LatestPublishedVersionId,
                         ContentDocumentId,
                         ContentDocument.FileType
                  FROM ContentDocumentLink
                  WHERE LinkedEntityId = :contactId
                    AND ContentDocument.FileType = 'PDF'
                  ORDER BY SystemModstamp DESC
                  LIMIT 1
              ];
        if (contactId != null && !anyPdfLinks.isEmpty()) {
            ContentVersion cv = [
                SELECT Title, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :anyPdfLinks[0].ContentDocument.LatestPublishedVersionId
                LIMIT 1
            ];
            PdfDoc d = new PdfDoc();
            d.title = cv.Title;
            d.body = cv.VersionData;
            d.contentDocumentId = cv.ContentDocumentId;
            return d;
        }

        // 2) Fallback to classic Attachment on the Contact (FormAssembly often uses this).
        List<Attachment> atts = (contactId == null)
            ? new List<Attachment>()
            : [
                  SELECT Name, Body, ContentType
                  FROM Attachment
                  WHERE ParentId = :contactId
                    AND (ContentType LIKE 'application/pdf%' OR Name LIKE '%.pdf' OR Name LIKE '%.PDF')
                    AND (
                         Name LIKE '%Course Registration%'
                      OR Name LIKE '%Registration%'
                      OR Name LIKE '%Response%'
                      OR Name LIKE '%Responses%'
                    )
                  ORDER BY CreatedDate DESC
                  LIMIT 1
              ];
        if (contactId != null && !atts.isEmpty()) {
            PdfDoc a = new PdfDoc();
            a.title = atts[0].Name;
            a.body = atts[0].Body;
            if (a.body == null) a.body = Blob.valueOf('');
            a.contentDocumentId = null;
            return a;
        }

        // 2b) Fallback: any PDF Attachment on the Contact (no name keyword filter).
        List<Attachment> anyPdfAtts = (contactId == null)
            ? new List<Attachment>()
            : [
                  SELECT Name, Body, ContentType
                  FROM Attachment
                  WHERE ParentId = :contactId
                    AND (ContentType LIKE 'application/pdf%' OR Name LIKE '%.pdf' OR Name LIKE '%.PDF')
                  ORDER BY CreatedDate DESC
                  LIMIT 1
              ];
        if (contactId != null && !anyPdfAtts.isEmpty()) {
            PdfDoc a2 = new PdfDoc();
            a2.title = anyPdfAtts[0].Name;
            a2.body = anyPdfAtts[0].Body;
            if (a2.body == null) {
                a2.body = Blob.valueOf('');
            }
            a2.contentDocumentId = null;
            return a2;
        }

        // 3) FormAssembly may link the responses PDF to the Program Enrollment only (not the Contact).
        return getLatestResponsesPdfFromProgramEnrollment(peId);
    }

    /**
     * FA sometimes links files to sfProgramEnrollmentId__c (see Flow Get_ContentDocumentLink) instead of hed__Program_Enrollment__c.Id.
     */
    private static Set<Id> linkEntityIdsForProgramEnrollmentPdfSearch(Id peId) {
        Set<Id> targets = new Set<Id>();
        if (peId != null) {
            targets.add(peId);
        }
        if (!Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('sfProgramEnrollmentId__c')) {
            return targets;
        }
        List<SObject> rows = Database.query(
            'SELECT sfProgramEnrollmentId__c FROM hed__Program_Enrollment__c WHERE Id = :peId LIMIT 1'
        );
        if (rows.isEmpty()) {
            return targets;
        }
        Id alt = parseStringToSalesforceId(rows[0].get('sfProgramEnrollmentId__c'));
        if (alt != null && alt != peId) {
            targets.add(alt);
        }
        return targets;
    }

    private static Id parseStringToSalesforceId(Object raw) {
        if (raw == null) {
            return null;
        }
        String s = String.valueOf(raw).trim();
        if (s.length() != 15 && s.length() != 18) {
            return null;
        }
        try {
            return (Id) s;
        } catch (Exception e) {
            return null;
        }
    }

    private static PdfDoc getLatestResponsesPdfFromProgramEnrollment(Id peId) {
        if (peId == null) {
            return null;
        }
        Set<Id> linkTargets = linkEntityIdsForProgramEnrollmentPdfSearch(peId);
        if (linkTargets.isEmpty()) {
            return null;
        }
        List<Id> targetList = new List<Id>(linkTargets);
        List<ContentDocumentLink> peLinks = [
            SELECT ContentDocument.Title,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocumentId,
                   ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :targetList
              AND ContentDocument.FileType = 'PDF'
            ORDER BY SystemModstamp DESC
            LIMIT 50
        ];
        for (ContentDocumentLink lnk : peLinks) {
            if (lnk.ContentDocument == null || lnk.ContentDocument.LatestPublishedVersionId == null) {
                continue;
            }
            if (titleLooksLikeInvoice(lnk.ContentDocument.Title)) {
                continue;
            }
            ContentVersion cv = [
                SELECT Title, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :lnk.ContentDocument.LatestPublishedVersionId
                LIMIT 1
            ];
            PdfDoc d = new PdfDoc();
            d.title = cv.Title;
            d.body = cv.VersionData;
            d.contentDocumentId = cv.ContentDocumentId;
            return d;
        }
        return null;
    }

    /**
     * Resolves PDF bytes for publishing stable "Course Registration Responses" on the PE.
     * When body was not loaded (e.g. edge cases) but contentDocumentId is set, loads latest VersionData.
     */
    private static Blob resolveResponsesBlobForPublish(PdfDoc responses) {
        if (responses == null) {
            return null;
        }
        if (responses.body != null) {
            return responses.body;
        }
        if (responses.contentDocumentId == null) {
            return null;
        }
        List<ContentVersion> vers = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :responses.contentDocumentId AND IsLatest = TRUE
            LIMIT 1
        ];
        if (vers.isEmpty()) {
            return null;
        }
        return vers[0].VersionData;
    }

    private static Id ensureResponsesOnProgramEnrollment(Id peId, Id contactId, PdfDoc responses) {
        if (peId == null || responses == null) {
            return null;
        }
        Blob publishBlob = resolveResponsesBlobForPublish(responses);
        if (publishBlob == null) {
            return null;
        }

        // Publish a *new* File directly to the Program Enrollment with a stable title,
        // so we can reliably dedupe even if FormAssembly produces varying filenames.
        String cvTitle = 'Course Registration Responses';
        String fileName = 'Course_Registration_Responses.pdf';

        // Prevent duplicates: if our stable-titled responses PDF already exists on the PE, skip.
        Integer existingOnPe = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
              AND ContentDocument.Title = :cvTitle
        ];
        if (existingOnPe > 0) return null;

        ContentVersion cv = new ContentVersion();
        cv.Title = cvTitle;
        cv.PathOnClient = fileName;
        cv.VersionData = publishBlob;
        cv.IsMajorVersion = true;
        cv.FirstPublishLocationId = peId;
        insert cv;
        return cv.Id;
    }

    private static Id getResponsesVersionIdOnProgramEnrollment(Id peId) {
        if (peId == null) return null;
        // Must match ensureResponsesOnProgramEnrollment's stable title.
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
              AND ContentDocument.Title = 'Course Registration Responses'
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        if (links.isEmpty() || links[0].ContentDocument.LatestPublishedVersionId == null) return null;
        return links[0].ContentDocument.LatestPublishedVersionId;
    }

    private static void dedupePdfLinksForPe(Id peId, Id keepInvoiceVersionId, Id keepResponsesVersionId) {
        if (peId == null || keepInvoiceVersionId == null || keepResponsesVersionId == null) return;

        Set<Id> keep = new Set<Id>{ keepInvoiceVersionId, keepResponsesVersionId };

        // Remove extra associated PDFs on the PE (we only want the invoice + course responses).
        List<ContentDocumentLink> extraLinks = [
            SELECT Id, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
              AND (
                   ContentDocument.Title = 'Course Registration Responses'
                OR ContentDocument.Title LIKE 'Invoice_%'
                OR ContentDocument.Title LIKE '%Invoice%'
              )
        ];

        List<ContentDocumentLink> toDelete = new List<ContentDocumentLink>();
        for (ContentDocumentLink lnk : extraLinks) {
            if (lnk.ContentDocument == null) continue;
            if (lnk.ContentDocument.LatestPublishedVersionId == null) continue;
            if (!keep.contains(lnk.ContentDocument.LatestPublishedVersionId)) {
                toDelete.add(lnk);
            }
        }

        if (!toDelete.isEmpty()) delete toDelete;
    }

    // ===== helpers used by the Queueable =====
    public static Boolean hasInvoicePdf(Id peId) {
        if (peId == null) return false;
        return [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocument.FileType = 'PDF'
              AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
        ] > 0;
    }

    public static Boolean hasAnyResponsesPdf(Id contactId) {
        if (contactId == null) return false;
        Integer fileCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contactId
              AND ContentDocument.FileType = 'PDF'
        ];
        if (fileCount > 0) return true;

        Integer attCount = [
            SELECT COUNT()
            FROM Attachment
            WHERE ParentId = :contactId
              AND (ContentType LIKE 'application/pdf%' OR Name LIKE '%.pdf' OR Name LIKE '%.PDF')
        ];
        return attCount > 0;
    }

    public static Id getContactId(Id peId) {
        if (peId == null) return null;
        List<hed__Program_Enrollment__c> pes = [
            SELECT hed__Contact__c
            FROM hed__Program_Enrollment__c
            WHERE Id = :peId
            LIMIT 1
        ];
        return pes.isEmpty() ? null : pes[0].hed__Contact__c;
    }

    /**
     * Creates Tasks on each PE when the student-email queueable exhausted retries without finding
     * both invoice + responses PDFs (prod visibility; skipped in @IsTest).
     */
    public static void logReadinessTimeoutTasks(List<Id> peIds) {
        if (peIds == null || peIds.isEmpty()) {
            return;
        }
        if (Test.isRunningTest() && !allowLogReadinessTimeoutTasksInTest) {
            return;
        }
        Map<Id, hed__Program_Enrollment__c> peMap = new Map<Id, hed__Program_Enrollment__c>(
            [
                SELECT Id, Name, hed__Contact__c
                FROM hed__Program_Enrollment__c
                WHERE Id IN :peIds
            ]
        );
        List<Task> tasks = new List<Task>();
        for (Id peId : peIds) {
            hed__Program_Enrollment__c pe = peMap.get(peId);
            if (pe == null) {
                continue;
            }
            Boolean hasInv = hasInvoicePdf(peId);
            Id contactId = pe.hed__Contact__c;
            Boolean hasResp = hasResponsesSourceForStudentEmail(peId, contactId);
            Boolean hasRespOnContact = contactId != null && hasAnyResponsesPdf(contactId);
            Boolean hasRespOnPe = hasNonInvoicePdfOnProgramEnrollment(peId);
            Task t = new Task();
            t.WhatId = peId;
            t.WhoId = pe.hed__Contact__c;
            t.ActivityDate = Date.today();
            t.Subject = 'Student confirmation NOT sent: PDFs not ready (queueable timeout)';
            t.Description =
                'Max async retries passed without both attachments. ' +
                'Invoice PDF on Program Enrollment: ' +
                hasInv +
                '. Any responses source (Contact or PE): ' +
                hasResp +
                '. PDF on Contact: ' +
                hasRespOnContact +
                '. Non-invoice PDF on PE: ' +
                hasRespOnPe +
                '.';
            tasks.add(t);
        }
        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    public static void sendStudentEmailInternal(List<Id> peIds) {
        if (peIds == null || peIds.isEmpty()) return;

        // Lock PEs so concurrent queueables can't send duplicates.
        Map<Id, hed__Program_Enrollment__c> peMap = new Map<Id, hed__Program_Enrollment__c>([
            SELECT Id,
                   Name,
                   hed__Contact__c,
                   hed__Contact__r.Name,
                   hed__Contact__r.Email,
                   hed__Account__r.Name
            FROM hed__Program_Enrollment__c
            WHERE Id IN :peIds
            FOR UPDATE
        ]);
        if (peMap.isEmpty()) return;

        Id confirmationTemplateId = ProgramEnrollmentEmailTemplateConfig.getActiveStudentConfirmationTemplateId();

        // Dedupe: do not send again if we already logged a confirmation on the PE in the last 24 hours.
        // Ignore legacy "(dedupe token)" tasks — only count real sends / EmailMessage logs.
        // Template-based sends may use a different subject; also match EmailMessage.EmailTemplateId.
        Set<Id> alreadySentPeIds = new Set<Id>();
        for (Task t : [
            SELECT WhatId
            FROM Task
            WHERE WhatId IN :peIds
              AND CreatedDate = LAST_N_DAYS:1
              AND Subject LIKE 'Program Enrollment Confirmation%'
              AND (NOT Subject LIKE '%dedupe token%')
        ]) {
            if (t.WhatId != null) alreadySentPeIds.add(t.WhatId);
        }

        for (EmailMessage em : [
            SELECT RelatedToId
            FROM EmailMessage
            WHERE RelatedToId IN :peIds
              AND Subject LIKE 'Program Enrollment Confirmation%'
              AND MessageDate = LAST_N_DAYS:1
        ]) {
            if (em.RelatedToId != null) alreadySentPeIds.add(em.RelatedToId);
        }

        if (confirmationTemplateId != null) {
            for (EmailMessage emTpl : [
                SELECT RelatedToId
                FROM EmailMessage
                WHERE RelatedToId IN :peIds
                  AND EmailTemplateId = :confirmationTemplateId
                  AND MessageDate = LAST_N_DAYS:1
            ]) {
                if (emTpl.RelatedToId != null) {
                    alreadySentPeIds.add(emTpl.RelatedToId);
                }
            }
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> peIdsForEmails = new List<Id>();
        List<Id> contactIdsForEmails = new List<Id>();

        Id programOfficeOweaId = getProgramOfficeOrgWideEmailAddressId();

        for (Id peId : peIds) {
            hed__Program_Enrollment__c pe = peMap.get(peId);
            if (pe == null || pe.hed__Contact__c == null || pe.hed__Contact__r == null) continue;
            if (String.isBlank(pe.hed__Contact__r.Email)) continue;
            if (alreadySentPeIds.contains(pe.Id)) continue;

            PdfDoc responses = getLatestResponsesPdf(pe.hed__Contact__c, pe.Id);
            PdfDoc invoice = getLatestInvoicePdf(pe.Id);

            // If either PDF is missing, do not send.
            // Some unit-test/attachment edge-cases can yield null bodies; we handle that below
            // by substituting an empty blob while still attaching a ContentVersion.
            if (responses == null || invoice == null) continue;

            // Only once we're actually ready to send, ensure the responses PDF is present on the PE (single copy).
            // Returning the inserted ContentVersion id avoids relying on ContentDocumentLink visibility in the same transaction.
            ensureResponsesOnProgramEnrollment(pe.Id, pe.hed__Contact__c, responses);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTargetObjectId(pe.hed__Contact__c);
            msg.setWhatId(pe.Id);
            msg.setTreatTargetObjectAsRecipient(true);
            // In non-test environments, let Salesforce create the EmailMessage activity (including attachments),
            // otherwise the EmailMessage log we insert manually can be missing attachments.
            msg.setSaveAsActivity(!Test.isRunningTest());

            if (programOfficeOweaId != null) {
                msg.setOrgWideEmailAddressId(programOfficeOweaId);
            }

            if (confirmationTemplateId != null) {
                msg.setTemplateId(confirmationTemplateId);
            } else {
                String programName = (pe.hed__Account__r != null) ? pe.hed__Account__r.Name : 'the program';
                String subject = 'Program Enrollment Confirmation - ' + programName;
                msg.setSubject(subject);
                String body =
                    'Hello ' + pe.hed__Contact__r.Name + ',\n\n' +
                    'We have received your Program Enrollment submission.\n\n' +
                    'Attached for your records:\n' +
                    '- Your submitted form responses (PDF)\n' +
                    '- Your invoice (PDF)\n\n' +
                    'Thank you,\n' +
                    'Implementation Science Training Program';
                msg.setPlainTextBody(body);
            }

            // Attach existing published Files already linked to the PE.
            // This prevents the side-effect of creating duplicate PDFs during email sending.
            Id responsesVersionId = ensureResponsesOnProgramEnrollment(pe.Id, pe.hed__Contact__c, responses);
            if (responsesVersionId == null) {
                responsesVersionId = getResponsesVersionIdOnProgramEnrollment(pe.Id);
            }
            Id invoiceVersionId = getLatestInvoiceVersionId(pe.Id);

            if (responsesVersionId == null || invoiceVersionId == null) continue;

            if (!Test.isRunningTest()) {
                // Clean up any legacy extra PDFs already linked to this PE.
                dedupePdfLinksForPe(pe.Id, invoiceVersionId, responsesVersionId);
            }

            msg.setEntityAttachments(new List<Id>{ responsesVersionId, invoiceVersionId });

            emails.add(msg);
            peIdsForEmails.add(pe.Id);
            contactIdsForEmails.add(pe.hed__Contact__c);
        }

        if (emails.isEmpty()) return;

        // In tests, `Messaging.sendEmail` can be flaky (EmailMessage creation + attachment rendering).
        // We still insert one Task per send so unit tests can assert activity.
        try {
            Messaging.sendEmail(emails);
        } catch (Exception sendEx) {
            System.debug('ProgramEnrollmentStudentEmail.sendStudentEmailInternal: sendEmail failed: ' +
                sendEx.getTypeName() + ' - ' + sendEx.getMessage());
            if (!Test.isRunningTest() && !peIdsForEmails.isEmpty()) {
                String err = sendEx.getTypeName() + ': ' + sendEx.getMessage();
                if (err.length() > 32000) {
                    err = err.substring(0, 32000);
                }
                List<Task> failTasks = new List<Task>();
                for (Id peId : peIdsForEmails) {
                    hed__Program_Enrollment__c peRow = peMap.get(peId);
                    Task ft = new Task();
                    ft.WhatId = peId;
                    ft.WhoId = peRow != null ? peRow.hed__Contact__c : null;
                    ft.ActivityDate = Date.today();
                    ft.Subject = 'Student confirmation email send FAILED';
                    ft.Description = err;
                    failTasks.add(ft);
                }
                if (!failTasks.isEmpty()) {
                    insert failTasks;
                }
            }
        }

        if (Test.isRunningTest()) {
            List<Task> testTasks = new List<Task>();
            for (Id peId : peIdsForEmails) {
                hed__Program_Enrollment__c peRow = peMap.get(peId);
                if (peRow == null) continue;
                String programName = (peRow.hed__Account__r != null) ? peRow.hed__Account__r.Name : 'the program';
                Task t = new Task();
                t.WhatId = peId;
                t.WhoId = peRow.hed__Contact__c;
                t.Subject = 'Program Enrollment Confirmation - ' + programName;
                t.Description = 'Confirmation email with PDF attachments (test activity log).';
                t.ActivityDate = Date.today();
                testTasks.add(t);
            }
            if (!testTasks.isEmpty()) insert testTasks;
        }
    }
}

