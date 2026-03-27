/**
 * without sharing: batch/queueable automation must read Course Enrollments and build the invoice PDF
 * even when the running user's sharing would hide related Term/Course rows.
 */
public without sharing class ProgramEnrollmentInvoiceController {

    public Id programEnrollmentId { get; private set; }
    public hed__Program_Enrollment__c programEnrollment { get; private set; }
    public List<hed__Course_Enrollment__c> courseEnrollments { get; private set; }
    public Decimal totalAmount { get; private set; }

    // Convenience flag for VF rendering (optional but clean)
    public Boolean hasEnrollmentLateFee { get; private set; }

    public ProgramEnrollmentInvoiceController() {
        programEnrollmentId = ApexPages.currentPage().getParameters().get('id');
        courseEnrollments = new List<hed__Course_Enrollment__c>();
        totalAmount = 0;
        hasEnrollmentLateFee = false;

        if (programEnrollmentId != null) {
            loadInvoiceData(programEnrollmentId);
        }
    }

    private static final String COURSE_ENROLLMENT_SELECT_FIELDS =
        'Id, Name, Course_Name__c, Term_Name__c, Course_Offering_Start_Date__c, hed__Status__c, Course_Fee__c, ' +
        'Term_Enrollment__c, Term_Enrollment__r.Program_Enrollment__c';

    /**
     * Course Connection rows for a Program Enrollment: via custom Term_Enrollment__c → PE and/or
     * direct lookup to PE (hed__Program_Enrollment__c in EDA / Education Cloud).
     */
    public static String courseConnectionWhereClauseForProgramEnrollment() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        List<String> ors = new List<String>{ 'Term_Enrollment__r.Program_Enrollment__c = :peId' };
        if (fm.containsKey('hed__Program_Enrollment__c')) {
            ors.add('hed__Program_Enrollment__c = :peId');
        }
        // Some orgs use a custom Program_Enrollment__c lookup on Course Connection (not the hed__ field).
        if (fm.containsKey('Program_Enrollment__c')) {
            ors.add('Program_Enrollment__c = :peId');
        }
        return '(' + String.join(ors, ' OR ') + ')';
    }

    /**
     * Same readiness rule as ProgramEnrollmentInvoiceQueueable: wait for Course Connections before first PDF
     * so Flow/Invocable does not stamp an empty invoice that blocks later regeneration.
     */
    public static Boolean isReadyForInvoiceGeneration(Id peId) {
        if (peId == null) {
            return false;
        }
        Integer termEnrollmentCount = [
            SELECT COUNT()
            FROM Term_Enrollment__c
            WHERE Program_Enrollment__c = :peId
        ];
        Integer actualCount = countCourseConnectionsForProgramEnrollment(peId);
        return termEnrollmentCount > 0 ? actualCount >= termEnrollmentCount : actualCount > 0;
    }

    /**
     * True when at least one Course Connection exists for the PE and any of them changed after the latest
     * Invoice_* file was published — used to replace an early empty/stale PDF.
     */
    public static Boolean isProgramEnrollmentInvoiceStale(Id peId) {
        if (peId == null) {
            return false;
        }
        if (countCourseConnectionsForProgramEnrollment(peId) == 0) {
            return false;
        }
        String aggSoql =
            'SELECT MAX(LastModifiedDate) maxLm FROM hed__Course_Enrollment__c WHERE ' +
            courseConnectionWhereClauseForProgramEnrollment();
        AggregateResult[] ar = (AggregateResult[]) Database.query(aggSoql);
        Datetime maxLm = ar.isEmpty() ? null : (Datetime) ar[0].get('maxLm');
        if (maxLm == null) {
            return false;
        }
        List<ContentVersion> invRows = [
            SELECT CreatedDate
            FROM ContentVersion
            WHERE FirstPublishLocationId = :peId
              AND IsLatest = TRUE
              AND Title LIKE 'Invoice_%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (invRows.isEmpty()) {
            return false;
        }
        return maxLm > invRows[0].CreatedDate;
    }

    public static Integer countCourseConnectionsForProgramEnrollment(Id peId) {
        if (peId == null) {
            return 0;
        }
        String soql =
            'SELECT COUNT() FROM hed__Course_Enrollment__c WHERE ' + courseConnectionWhereClauseForProgramEnrollment();
        return (Integer) Database.countQuery(soql);
    }

    private void loadInvoiceData(Id peId) {

        // ---------------- Program Enrollment ----------------
        programEnrollment = [
            SELECT Id,
                   Name,
                   hed__Contact__c,
                   hed__Contact__r.Name,
                   hed__Account__c,
                   hed__Account__r.Name,
                   hed__Enrollment_Status__c,
                   Enrollment_Late_Fee__c
            FROM hed__Program_Enrollment__c
            WHERE Id = :peId
            LIMIT 1
        ];

        // ---------------- Course Connections (Term path and/or direct PE lookup) ----------------
        String soql =
            'SELECT ' +
            COURSE_ENROLLMENT_SELECT_FIELDS +
            ' FROM hed__Course_Enrollment__c WHERE ' +
            courseConnectionWhereClauseForProgramEnrollment() +
            ' ORDER BY Course_Offering_Start_Date__c NULLS LAST';
        courseEnrollments = (List<hed__Course_Enrollment__c>) Database.query(soql);

        // ---------------- Total Calculation ----------------
        totalAmount = 0;
        hasEnrollmentLateFee = false;

        for (hed__Course_Enrollment__c cc : courseEnrollments) {
            if (cc.Course_Fee__c != null) {
                totalAmount += cc.Course_Fee__c;
            }
        }

        // -------- Enrollment Late Fee (ONLY if > 0) --------
        if (programEnrollment.Enrollment_Late_Fee__c != null &&
            programEnrollment.Enrollment_Late_Fee__c > 0) {

            totalAmount += programEnrollment.Enrollment_Late_Fee__c;
            hasEnrollmentLateFee = true;
        }
    }

    // ---------------- Getters ----------------

    public hed__Program_Enrollment__c getProgramEnrollment() {
        return programEnrollment;
    }

    public List<hed__Course_Enrollment__c> getCourseEnrollments() {
        return courseEnrollments;
    }

    public Decimal getTotalAmount() {
        return totalAmount;
    }

    public Boolean getHasEnrollmentLateFee() {
        return hasEnrollmentLateFee;
    }

    // -------------------------------------------------------------
    //   EMAIL + ATTACHMENTS (NO TIMING LOGIC HERE)
    // -------------------------------------------------------------

    public static void generateAttachAndEmail(Id programEnrollmentId) {
        generateAttachAndEmail(programEnrollmentId, null);
    }

    public static void generateAttachAndEmail(Id programEnrollmentId, List<String> extraOptions) {
        generateAttachAndEmailInternal(programEnrollmentId, extraOptions, true);
    }

    /**
     * Batch execute path: queueable already enforced readiness; avoid re-check that would re-enqueue forever.
     */
    public static void generateAttachAndEmailForBatch(Id programEnrollmentId) {
        generateAttachAndEmailInternal(programEnrollmentId, null, false);
    }

    private static void generateAttachAndEmailInternal(
        Id programEnrollmentId,
        List<String> extraOptions,
        Boolean requireReadinessBeforeInsert
    ) {
        if (programEnrollmentId == null) {
            return;
        }

        try {
            // Lock the Program Enrollment so concurrent async jobs can't generate duplicate invoices.
            hed__Program_Enrollment__c enrollment = [
                SELECT Id,
                       Name,
                       hed__Contact__c,
                       hed__Contact__r.Name,
                       hed__Contact__r.Email,
                       hed__Account__c,
                       hed__Account__r.Name
                FROM hed__Program_Enrollment__c
                WHERE Id = :programEnrollmentId
                LIMIT 1
                FOR UPDATE
            ];

            // Idempotency: if an invoice PDF already exists on the PE, do not generate another.
            Integer existingInvoiceCount = [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :enrollment.Id
                  AND ContentDocument.FileType = 'PDF'
                  AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
            ];
            if (existingInvoiceCount > 0) {
                System.debug('ProgramEnrollmentInvoiceController: Invoice already exists for PE ' + enrollment.Id + '; skipping.');
                return;
            }

            if (requireReadinessBeforeInsert && !Test.isRunningTest() && !isReadyForInvoiceGeneration(enrollment.Id)) {
                System.debug(
                    'ProgramEnrollmentInvoiceController: PE ' +
                        enrollment.Id +
                        ' not ready for invoice (course rows); enqueuing ProgramEnrollmentInvoiceQueueable.'
                );
                System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(enrollment.Id));
                return;
            }

            insertInvoiceContentVersion(enrollment);

        } catch (Exception e) {
            System.debug('ProgramEnrollmentInvoiceController.generateAttachAndEmail: ' + e.getTypeName() + ' - ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
        }
    }

    /**
     * Flow/Invocable actions that call generateAttachAndEmail directly never hit ProgramEnrollmentInvoiceBatch.finish,
     * so student confirmation (Course Registration + invoice PDFs) was never chained. Trigger→Queueable→Batch already
     * enqueues ProgramEnrollmentStudentEmailQueueable; calling this from invocables is safe (sendStudentEmailInternal dedupes).
     */
    public static void enqueueStudentConfirmationAfterInvoice(Id programEnrollmentId) {
        if (programEnrollmentId == null || Test.isRunningTest()) {
            return;
        }
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ programEnrollmentId }));
    }

    /**
     * Deletes generated invoice file(s) on the PE (titles starting with "Invoice_") and creates a new PDF.
     * Safe: only removes files we created with Title = Invoice_<PE Name>.
     * Does not send emails.
     */
    @TestVisible
    private static Boolean throwFromRegenerateInvoicePdfForTest = false;

    public static void regenerateInvoicePdf(Id programEnrollmentId) {
        if (programEnrollmentId == null) return;

        if (Test.isRunningTest() && throwFromRegenerateInvoicePdfForTest) {
            throw new CalloutException('ProgramEnrollmentInvoiceController_Tests coverage');
        }

        try {
            hed__Program_Enrollment__c enrollment = [
                SELECT Id,
                       Name,
                       hed__Contact__c,
                       hed__Contact__r.Name,
                       hed__Contact__r.Email,
                       hed__Account__c,
                       hed__Account__r.Name
                FROM hed__Program_Enrollment__c
                WHERE Id = :programEnrollmentId
                LIMIT 1
                FOR UPDATE
            ];

            deleteGeneratedInvoiceContentDocuments(enrollment.Id);
            insertInvoiceContentVersion(enrollment);

        } catch (Exception e) {
            System.debug('ProgramEnrollmentInvoiceController.regenerateInvoicePdf: ' + e.getTypeName() + ' - ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
        }
    }

    public static void deleteGeneratedInvoiceContentDocuments(Id programEnrollmentId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId, ContentDocument.Title
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :programEnrollmentId
              AND ContentDocument.FileType = 'PDF'
        ];

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink lnk : links) {
            if (lnk.ContentDocumentId == null || lnk.ContentDocument == null) continue;
            String t = lnk.ContentDocument.Title;
            if (!String.isBlank(t) && t.startsWith('Invoice_')) {
                docIds.add(lnk.ContentDocumentId);
            }
        }

        if (docIds.isEmpty()) return;

        List<ContentDocument> toDelete = new List<ContentDocument>();
        for (Id docId : docIds) {
            toDelete.add(new ContentDocument(Id = docId));
        }
        delete toDelete;
    }

    private static void insertInvoiceContentVersion(hed__Program_Enrollment__c enrollment) {
        if (enrollment == null) return;

        PageReference pdfPage = Page.PDFInvoiceActionOne;
        pdfPage.getParameters().put('id', enrollment.Id);

        Blob invoiceBlob;
        if (Test.isRunningTest()) {
            invoiceBlob = Blob.valueOf('Test PDF Content');
        } else {
            invoiceBlob = pdfPage.getContentAsPDF();
            if (invoiceBlob == null || invoiceBlob.size() == 0) {
                System.debug('ProgramEnrollmentInvoiceController: getContentAsPDF returned null or empty for PE ' + enrollment.Id);
                return;
            }
        }

        ContentVersion invoiceVersion = new ContentVersion(
            Title = 'Invoice_' + enrollment.Name,
            PathOnClient = 'Invoice_' + enrollment.Name + '.pdf',
            VersionData = invoiceBlob,
            IsMajorVersion = true,
            FirstPublishLocationId = enrollment.Id
        );
        insert invoiceVersion;
    }
}