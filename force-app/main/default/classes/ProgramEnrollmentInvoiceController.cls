public with sharing class ProgramEnrollmentInvoiceController {

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

        // ---------------- Course Enrollments ----------------
        courseEnrollments = [
            SELECT Id,
                   Name,
                   Course_Name__c,
                   Term_Name__c,
                   Course_Offering_Start_Date__c,
                   hed__Status__c,
                   Course_Fee__c,
                   Term_Enrollment__c,
                   Term_Enrollment__r.Program_Enrollment__c
            FROM hed__Course_Enrollment__c
            WHERE Term_Enrollment__r.Program_Enrollment__c = :peId
            ORDER BY Course_Offering_Start_Date__c
        ];

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

        if (programEnrollmentId == null) return;

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

            insertInvoiceContentVersion(enrollment);

        } catch (Exception e) {
            System.debug('ProgramEnrollmentInvoiceController.generateAttachAndEmail: ' + e.getTypeName() + ' - ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
        }
    }

    /**
     * Deletes generated invoice file(s) on the PE (titles starting with "Invoice_") and creates a new PDF.
     * Safe: only removes files we created with Title = Invoice_<PE Name>.
     * Does not send emails.
     */
    public static void regenerateInvoicePdf(Id programEnrollmentId) {
        if (programEnrollmentId == null) return;

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

    private static void deleteGeneratedInvoiceContentDocuments(Id programEnrollmentId) {
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