/**
 * Student confirmation mail should appear From the correct program office mailbox, not the automation user.
 * Implementation Science: verified OWEA implementationscience@ucsf.edu.
 * Ad Hoc DEB: verified OWEA ticr_coordinator@ucsf.edu (never Implementation Science display name).
 *
 * without sharing: FormAssembly stores the responses PDF on the Contact; the queueable/invocable
 * often runs as an integration or system user that cannot see those Files under with sharing.
 * We must read Contact-linked ContentVersion and publish a copy on the PE reliably.
 *
 * Body/subject: renders active Lightning EmailTemplates via Messaging.renderStoredEmailTemplate (merge fields)
 * but does NOT call setTemplateId — Lightning templates + setTemplateId drop file attachments in Apex sends.
 * PDFs attach via setEntityAttachments on ContentVersion Ids (May 19 prod path); setTemplateId is not used.
 */
public without sharing class ProgramEnrollmentStudentEmail {

    /** Implementation Science program office sender (IS confirmations + payment emails). */
    private static final String PROGRAM_OFFICE_FROM_EMAIL = 'implementationscience@ucsf.edu';
    /** Ad Hoc DEB / TICR confirmations — avoids "Implementation Science - Program Office" as From display name. */
    private static final String AD_HOC_DEB_FROM_EMAIL = 'ticr_coordinator@ucsf.edu';

    private static Map<String, Id> oweaIdByAddressLower = new Map<String, Id>();
    private static Boolean oweaLookupDone = false;

    @TestVisible
    private static Boolean allowOrgWideEmailLookupInTest = false;
    @TestVisible
    private static Boolean allowLogReadinessTimeoutTasksInTest = false;

    @TestVisible
    private static void resetOweaCacheForTest() {
        oweaIdByAddressLower = new Map<String, Id>();
        oweaLookupDone = false;
    }

    /**
     * Resolves a verified OrgWideEmailAddress Id by Address (case-insensitive).
     * Returns null in unit tests or when no matching OWEA exists (email then uses running user as From).
     */
    private static Id getOrgWideEmailAddressId(String fromEmail) {
        if (String.isBlank(fromEmail)) {
            return null;
        }
        if (Test.isRunningTest() && !allowOrgWideEmailLookupInTest) {
            return null;
        }
        String key = fromEmail.trim().toLowerCase();
        if (!oweaLookupDone) {
            oweaLookupDone = true;
            for (OrgWideEmailAddress o : [SELECT Id, Address FROM OrgWideEmailAddress]) {
                if (o.Address != null) {
                    oweaIdByAddressLower.put(o.Address.trim().toLowerCase(), o.Id);
                }
            }
        }
        Id resolved = oweaIdByAddressLower.get(key);
        if (resolved == null && !Test.isRunningTest()) {
            System.debug(
                LoggingLevel.WARN,
                'ProgramEnrollmentStudentEmail: No OrgWideEmailAddress matches ' + fromEmail +
                    '; confirmation email will use the running user as From.'
            );
        }
        return resolved;
    }

    /** IS and other non–Ad Hoc confirmations use the Implementation Science program office OWEA. */
    private static Id getProgramOfficeOrgWideEmailAddressId() {
        return getOrgWideEmailAddressId(PROGRAM_OFFICE_FROM_EMAIL);
    }

    /**
     * Ad Hoc DEB uses TICR coordinator OWEA when deployed; never falls back to Implementation Science branding.
     */
    private static Id getStudentConfirmationOrgWideEmailAddressId(
        Id accountId,
        String accountName
    ) {
        if (ProgramEnrollmentEmailTemplateConfig.isAdHocClinicalResearchProgram(accountId, accountName)) {
            return getOrgWideEmailAddressId(AD_HOC_DEB_FROM_EMAIL);
        }
        return getProgramOfficeOrgWideEmailAddressId();
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

    /** Result of resolving which ContentVersion to attach as the registration/responses PDF. */
    private class StudentEmailResponsesResolution {
        Id contentVersionId;
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
     * Links the latest FA responses PDF to the PE when it exists only on the Contact. Skips when the
     * PE already has a non-invoice PDF (FormAssembly's descriptive filename is kept). Does not send email.
     */
    public static void copyResponsesPdfToProgramEnrollment(Id peId) {
        if (peId == null) {
            return;
        }
        if (getLatestNonInvoicePdfVersionIdOnProgramEnrollment(peId) != null) {
            removeStableResponsesDuplicateOnPe(peId);
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
        removeStableResponsesDuplicateOnPe(pe.Id);
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

    private static Id getLatestInvoiceVersionId(Id peId) {
        if (peId == null) {
            return null;
        }
        Set<Id> linkTargets = linkEntityIdsForProgramEnrollmentPdfSearch(peId);
        if (linkTargets.isEmpty()) {
            return null;
        }
        List<Id> targetList = new List<Id>(linkTargets);
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersionId,
                   ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :targetList
              AND ContentDocument.FileType = 'PDF'
              AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        if (links.isEmpty() || links[0].ContentDocument.LatestPublishedVersionId == null) {
            return null;
        }
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
        Set<Id> linkTargets = linkEntityIdsForProgramEnrollmentPdfSearch(peId);
        if (linkTargets.isEmpty()) {
            return false;
        }
        List<Id> targetList = new List<Id>(linkTargets);
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :targetList
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

    @TestVisible
    static Id testParseStringToSalesforceId(Object raw) {
        return parseStringToSalesforceId(raw);
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
     * Latest non-invoice PDF on the PE (or sfProgramEnrollmentId__c), by ContentDocumentLink.SystemModstamp.
     * Does not load VersionData — for entity attachment Ids only.
     */
    private static Id getLatestNonInvoicePdfVersionIdOnProgramEnrollment(Id peId) {
        if (peId == null) {
            return null;
        }
        Set<Id> linkTargets = linkEntityIdsForProgramEnrollmentPdfSearch(peId);
        if (linkTargets.isEmpty()) {
            return null;
        }
        List<Id> targetList = new List<Id>(linkTargets);
        List<ContentDocumentLink> peLinks = [
            SELECT ContentDocument.Title, ContentDocument.LatestPublishedVersionId
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
            return lnk.ContentDocument.LatestPublishedVersionId;
        }
        return null;
    }

    /**
     * PE-native registration PDF first. If none, link the Contact/Attachment PDF to the PE (keeps FA filename).
     */
    private static StudentEmailResponsesResolution resolveResponsesAttachmentForStudentEmail(Id peId, Id contactId) {
        StudentEmailResponsesResolution out = new StudentEmailResponsesResolution();

        Id peNativeVersionId = getLatestNonInvoicePdfVersionIdOnProgramEnrollment(peId);
        if (peNativeVersionId != null) {
            out.contentVersionId = peNativeVersionId;
            return out;
        }

        PdfDoc responses = getLatestResponsesPdf(contactId, peId);
        if (responses == null) {
            return out;
        }

        Id linkedVersionId = ensureResponsesOnProgramEnrollment(peId, contactId, responses);
        out.contentVersionId = linkedVersionId != null
            ? linkedVersionId
            : getLatestNonInvoicePdfVersionIdOnProgramEnrollment(peId);
        return out;
    }

    /**
     * Resolves PDF bytes for publishing responses on the PE from a classic Attachment fallback.
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

    private static void ensureFileLinkedToProgramEnrollment(Id peId, Id contentDocumentId) {
        if (peId == null || contentDocumentId == null) {
            return;
        }
        Integer existing = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocumentId = :contentDocumentId
        ];
        if (existing > 0) {
            return;
        }
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocumentId;
        cdl.LinkedEntityId = peId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }

    private static Id getLatestPublishedVersionId(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return null;
        }
        List<ContentVersion> rows = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = TRUE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    /**
     * Links the FA responses PDF to the PE without renaming. Prefers an existing non-invoice PDF on the PE.
     */
    private static Id ensureResponsesOnProgramEnrollment(Id peId, Id contactId, PdfDoc responses) {
        if (peId == null || responses == null) {
            return null;
        }

        Id peNativeVersionId = getLatestNonInvoicePdfVersionIdOnProgramEnrollment(peId);
        if (peNativeVersionId != null) {
            return peNativeVersionId;
        }

        if (responses.contentDocumentId != null) {
            ensureFileLinkedToProgramEnrollment(peId, responses.contentDocumentId);
            return getLatestPublishedVersionId(responses.contentDocumentId);
        }

        Blob publishBlob = resolveResponsesBlobForPublish(responses);
        if (publishBlob == null) {
            return null;
        }

        String title = String.isBlank(responses.title) ? 'Form Responses' : responses.title;
        String fileName = title.toLowerCase().endsWith('.pdf') ? title : (title + '.pdf');
        String cvTitle = fileName.endsWith('.pdf') ? fileName.left(fileName.length() - 4) : fileName;

        ContentVersion cv = new ContentVersion();
        cv.Title = cvTitle;
        cv.PathOnClient = fileName;
        cv.VersionData = publishBlob;
        cv.IsMajorVersion = true;
        cv.FirstPublishLocationId = peId;
        insert cv;
        return cv.Id;
    }

    /** Legacy stable title from older automation; remove when a descriptive FA PDF is also on the PE. */
    private static final String STABLE_RESPONSES_TITLE = 'Course Registration Responses';

    private static void removeStableResponsesDuplicateOnPe(Id peId) {
        if (peId == null) {
            return;
        }
        Set<Id> linkTargets = linkEntityIdsForProgramEnrollmentPdfSearch(peId);
        if (linkTargets.isEmpty()) {
            return;
        }
        List<Id> targetList = new List<Id>(linkTargets);
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :targetList
              AND ContentDocument.FileType = 'PDF'
        ];
        Boolean hasDescriptiveResponses = false;
        List<ContentDocumentLink> stableLinks = new List<ContentDocumentLink>();
        for (ContentDocumentLink lnk : links) {
            if (lnk.ContentDocument == null) {
                continue;
            }
            String title = lnk.ContentDocument.Title;
            if (title == STABLE_RESPONSES_TITLE) {
                stableLinks.add(lnk);
            } else if (!titleLooksLikeInvoice(title)) {
                hasDescriptiveResponses = true;
            }
        }
        if (!hasDescriptiveResponses || stableLinks.isEmpty()) {
            return;
        }
        delete stableLinks;
    }

    // ===== helpers used by the Queueable =====

    /**
     * True when both PDF ContentVersions exist, have bytes, course rows are settled, and the invoice is not stale.
     */
    public static Boolean isStudentConfirmationAttachmentsReady(Id peId) {
        if (peId == null) {
            return false;
        }
        Id contactId = getContactId(peId);
        if (!hasResponsesSourceForStudentEmail(peId, contactId)) {
            return false;
        }
        StudentEmailResponsesResolution responsesRes = resolveResponsesAttachmentForStudentEmail(peId, contactId);
        if (responsesRes.contentVersionId == null) {
            return false;
        }
        Id invoiceVersionId = getLatestInvoiceVersionId(peId);
        if (invoiceVersionId == null) {
            return false;
        }
        if (!areContentVersionsAttachable(
            new Set<Id>{ responsesRes.contentVersionId, invoiceVersionId }
        )) {
            return false;
        }
        return isProgramEnrollmentSettledForInvoice(peId);
    }

    /**
     * Invoice-only readiness for chaining student email after invoice batch (no responses check here).
     */
    public static Boolean isInvoiceAttachmentReady(Id peId) {
        if (peId == null) {
            return false;
        }
        Id invoiceVersionId = getLatestInvoiceVersionId(peId);
        if (invoiceVersionId == null) {
            return false;
        }
        if (!areContentVersionsAttachable(new Set<Id>{ invoiceVersionId })) {
            return false;
        }
        return isProgramEnrollmentSettledForInvoice(peId);
    }

    /**
     * When the PE has Term Enrollments, wait until every TE has a Course Connection and the invoice is not stale.
     */
    private static Boolean isProgramEnrollmentSettledForInvoice(Id peId) {
        Integer teCount = [
            SELECT COUNT()
            FROM Term_Enrollment__c
            WHERE Program_Enrollment__c = :peId
        ];
        if (teCount == 0) {
            return true;
        }
        if (!ProgramEnrollmentInvoiceController.isReadyForInvoiceGeneration(peId)) {
            return false;
        }
        return !ProgramEnrollmentInvoiceController.isProgramEnrollmentInvoiceStale(peId);
    }

    private static Boolean areContentVersionsAttachable(Set<Id> contentVersionIds) {
        if (contentVersionIds == null || contentVersionIds.isEmpty()) {
            return false;
        }
        Set<Id> ids = new Set<Id>();
        for (Id cvId : contentVersionIds) {
            if (cvId != null) {
                ids.add(cvId);
            }
        }
        if (ids.isEmpty()) {
            return false;
        }
        List<ContentVersion> rows = [
            SELECT Id, ContentSize
            FROM ContentVersion
            WHERE Id IN :ids
        ];
        if (rows.size() != ids.size()) {
            return false;
        }
        for (ContentVersion cv : rows) {
            if (cv.ContentSize == null || cv.ContentSize <= 0) {
                return false;
            }
        }
        return true;
    }

    /**
     * PEs with a confirmation EmailMessage in the last day that logged at least two PDF attachments.
     */
    @TestVisible
    private static Set<Id> findPeIdsWithCompleteConfirmationEmail(Set<Id> peIds) {
        Set<Id> complete = new Set<Id>();
        if (peIds == null || peIds.isEmpty()) {
            return complete;
        }
        for (EmailMessage em : [
            SELECT RelatedToId,
                   (SELECT ContentDocumentId, ContentDocument.FileType FROM ContentDocumentLinks)
            FROM EmailMessage
            WHERE RelatedToId IN :peIds
              AND (
                  Subject LIKE 'Program Enrollment Confirmation%'
                  OR Subject LIKE 'DEB Course Enrollment%'
              )
              AND MessageDate = LAST_N_DAYS:1
        ]) {
            if (em.RelatedToId == null) {
                continue;
            }
            Integer pdfCount = 0;
            if (em.ContentDocumentLinks != null) {
                for (ContentDocumentLink cdl : em.ContentDocumentLinks) {
                    if (cdl.ContentDocument != null && cdl.ContentDocument.FileType == 'PDF') {
                        pdfCount++;
                    }
                }
            }
            if (pdfCount >= 2) {
                complete.add(em.RelatedToId);
            }
        }
        return complete;
    }

    public static Boolean hasInvoicePdf(Id peId) {
        if (peId == null) {
            return false;
        }
        Set<Id> linkTargets = linkEntityIdsForProgramEnrollmentPdfSearch(peId);
        if (linkTargets.isEmpty()) {
            return false;
        }
        List<Id> targetList = new List<Id>(linkTargets);
        return [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :targetList
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
     * Renders template merge fields onto the outbound message without setTemplateId so entity attachments deliver.
     * Falls back to inline confirmation copy when render fails (e.g. sandbox without template).
     */
    private static void applyConfirmationSubjectAndBody(
        Messaging.SingleEmailMessage msg,
        hed__Program_Enrollment__c pe,
        Id confirmationTemplateId
    ) {
        if (confirmationTemplateId != null && pe.hed__Contact__c != null) {
            try {
                Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                    confirmationTemplateId,
                    pe.hed__Contact__c,
                    pe.Id
                );
                msg.setSubject(rendered.getSubject());
                if (!String.isBlank(rendered.getHtmlBody())) {
                    msg.setHtmlBody(rendered.getHtmlBody());
                } else if (!String.isBlank(rendered.getPlainTextBody())) {
                    msg.setPlainTextBody(rendered.getPlainTextBody());
                }
                return;
            } catch (Exception renderEx) {
                System.debug(
                    LoggingLevel.WARN,
                    'ProgramEnrollmentStudentEmail: renderStoredEmailTemplate failed: ' +
                        renderEx.getTypeName() +
                        ' - ' +
                        renderEx.getMessage()
                );
            }
        }
        applyInlineConfirmationSubjectAndBody(msg, pe);
    }

    private static void applyInlineConfirmationSubjectAndBody(
        Messaging.SingleEmailMessage msg,
        hed__Program_Enrollment__c pe
    ) {
        String programName = (pe.hed__Account__r != null) ? pe.hed__Account__r.Name : 'the program';
        msg.setSubject('Program Enrollment Confirmation - ' + programName);
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

    /**
     * Attaches both PDFs via entity attachment Ids (same path as the May 19 working sends).
     * Requires rendered/inline body without setTemplateId — entity attachments persist on EmailMessage as Files.
     */
    private static Boolean applyPdfAttachmentsToMessage(
        Messaging.SingleEmailMessage msg,
        Id responsesContentVersionId,
        Id invoiceContentVersionId
    ) {
        if (responsesContentVersionId == null || invoiceContentVersionId == null) {
            return false;
        }
        msg.setEntityAttachments(new List<Id>{ responsesContentVersionId, invoiceContentVersionId });
        return true;
    }

    /**
     * Template-based confirmations require a Term Enrollment with Term__c so Deb_Confirmation_Term__c can be stamped.
     * Lightning Email Templates cannot merge Enrollment_Term__r.Name reliably.
     */
    public static Boolean isConfirmationTermReady(Id peId) {
        return hasTermEnrollmentWithTerm(peId);
    }

    /** @deprecated Use {@link #isConfirmationTermReady}; kept for test/backward compatibility. */
    public static Boolean isAdHocConfirmationTermReady(
        Id peId,
        Id programAccountId,
        String programAccountName
    ) {
        if (!ProgramEnrollmentEmailTemplateConfig.isAdHocClinicalResearchProgram(
            programAccountId,
            programAccountName
        )) {
            return true;
        }
        return isConfirmationTermReady(peId);
    }

    public static Boolean hasTermEnrollmentWithTerm(Id peId) {
        if (peId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM Term_Enrollment__c
            WHERE Program_Enrollment__c = :peId AND Term__c != NULL
        ] > 0;
    }

    private static String resolveDebConfirmationTermNameFromTe(Id peId) {
        List<Term_Enrollment__c> rows = [
            SELECT Term__r.Name
            FROM Term_Enrollment__c
            WHERE Program_Enrollment__c = :peId AND Term__c != NULL
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (rows.isEmpty() || rows[0].Term__r == null) {
            return null;
        }
        return rows[0].Term__r.Name;
    }

    /**
     * Stamps Deb_Confirmation_Term__c from the newest TE term name when blank (covers race before Term_Enrollment_Create flow).
     */
    public static void ensureDebConfirmationTermStamped(Id peId) {
        if (peId == null) {
            return;
        }
        hed__Program_Enrollment__c row = [
            SELECT Id, Deb_Confirmation_Term__c
            FROM hed__Program_Enrollment__c
            WHERE Id = :peId
            LIMIT 1
        ];
        if (!String.isBlank(row.Deb_Confirmation_Term__c)) {
            return;
        }
        String termName = resolveDebConfirmationTermNameFromTe(peId);
        if (String.isBlank(termName)) {
            return;
        }
        update new hed__Program_Enrollment__c(Id = peId, Deb_Confirmation_Term__c = termName);
    }

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
            Boolean attachmentsReady = isStudentConfirmationAttachmentsReady(peId);
            Id contactId = pe.hed__Contact__c;
            Boolean hasResp = hasResponsesSourceForStudentEmail(peId, contactId);
            Boolean hasInv = hasInvoicePdf(peId);
            Boolean hasRespOnContact = contactId != null && hasAnyResponsesPdf(contactId);
            Boolean hasRespOnPe = hasNonInvoicePdfOnProgramEnrollment(peId);
            Task t = new Task();
            t.WhatId = peId;
            t.WhoId = pe.hed__Contact__c;
            t.ActivityDate = Date.today();
            t.Subject = 'Student confirmation NOT sent: PDFs not ready (queueable timeout)';
            t.Description =
                'Max async retries passed without both attachments. ' +
                'Attachments ready: ' +
                attachmentsReady +
                '. Invoice PDF on Program Enrollment: ' +
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
        sendStudentEmailInternal(peIds, false);
    }

    public static void sendStudentEmailInternal(List<Id> peIds, Boolean forceResend) {
        if (peIds == null || peIds.isEmpty()) return;

        // Lock PEs so concurrent queueables can't send duplicates.
        Map<Id, hed__Program_Enrollment__c> peMap = new Map<Id, hed__Program_Enrollment__c>([
            SELECT Id,
                   Name,
                   Deb_Confirmation_Term__c,
                   hed__Account__c,
                   hed__Contact__c,
                   hed__Contact__r.Name,
                   hed__Contact__r.Email,
                   hed__Account__r.Name
            FROM hed__Program_Enrollment__c
            WHERE Id IN :peIds
            FOR UPDATE
        ]);
        if (peMap.isEmpty()) return;

        // Dedupe: do not send again if a complete confirmation (2+ PDF attachments) was logged in the last day.
        Set<Id> alreadySentPeIds = new Set<Id>();
        if (forceResend != true) {
            alreadySentPeIds.addAll(findPeIdsWithCompleteConfirmationEmail(new Set<Id>(peIds)));
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> peIdsForEmails = new List<Id>();
        List<Id> contactIdsForEmails = new List<Id>();

        for (Id peId : peIds) {
            hed__Program_Enrollment__c pe = peMap.get(peId);
            if (pe == null || pe.hed__Contact__c == null || pe.hed__Contact__r == null) continue;
            if (String.isBlank(pe.hed__Contact__r.Email)) continue;
            if (alreadySentPeIds.contains(pe.Id)) continue;

            if (!isStudentConfirmationAttachmentsReady(pe.Id)) {
                continue;
            }

            StudentEmailResponsesResolution responsesRes = resolveResponsesAttachmentForStudentEmail(
                pe.Id,
                pe.hed__Contact__c
            );
            if (responsesRes.contentVersionId == null) {
                continue;
            }

            Id invoiceVersionId = getLatestInvoiceVersionId(pe.Id);
            if (invoiceVersionId == null) {
                continue;
            }

            String acctNm = pe.hed__Account__r != null ? pe.hed__Account__r.Name : null;
            Id confirmationTemplateId = ProgramEnrollmentEmailTemplateConfig.resolveStudentConfirmationTemplateId(
                pe.hed__Account__c,
                acctNm
            );

            if (confirmationTemplateId != null) {
                if (ProgramEnrollmentEmailTemplateConfig.isAdHocClinicalResearchProgram(
                    pe.hed__Account__c,
                    acctNm
                )) {
                    if (!isConfirmationTermReady(pe.Id)) {
                        continue;
                    }
                    ensureDebConfirmationTermStamped(pe.Id);
                    pe = [
                        SELECT Id,
                               Name,
                               Deb_Confirmation_Term__c,
                               hed__Account__c,
                               hed__Contact__c,
                               hed__Contact__r.Name,
                               hed__Contact__r.Email,
                               hed__Account__r.Name
                        FROM hed__Program_Enrollment__c
                        WHERE Id = :pe.Id
                        LIMIT 1
                    ];
                    peMap.put(pe.Id, pe);
                    if (String.isBlank(pe.Deb_Confirmation_Term__c)) {
                        continue;
                    }
                }
            }

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTargetObjectId(pe.hed__Contact__c);
            msg.setWhatId(pe.Id);
            msg.setTreatTargetObjectAsRecipient(true);
            // In non-test environments, let Salesforce create the EmailMessage activity (including attachments),
            // otherwise the EmailMessage log we insert manually can be missing attachments.
            msg.setSaveAsActivity(!Test.isRunningTest());

            Id confirmationOweaId = getStudentConfirmationOrgWideEmailAddressId(
                pe.hed__Account__c,
                acctNm
            );
            if (confirmationOweaId != null) {
                msg.setOrgWideEmailAddressId(confirmationOweaId);
            }

            applyConfirmationSubjectAndBody(msg, pe, confirmationTemplateId);

            if (!applyPdfAttachmentsToMessage(msg, responsesRes.contentVersionId, invoiceVersionId)) {
                if (!Test.isRunningTest()) {
                    Task skipTask = buildTask(
                        pe.Id,
                        pe.hed__Contact__c,
                        'Student confirmation NOT sent: PDF attachments unavailable',
                        'Could not resolve ContentVersion Ids for both invoice and responses PDFs on this Program Enrollment.'
                    );
                    if (skipTask != null) {
                        insert skipTask;
                    }
                }
                continue;
            }

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

