public with sharing class ProgramEnrollmentInvoiceQueueable implements Queueable, Database.AllowsCallouts {

    private List<Id> peIds;
    private Integer retry;

    // Public constructors
    public ProgramEnrollmentInvoiceQueueable(Id peId) {
        this(new List<Id>{ peId }, 0);
    }

    public ProgramEnrollmentInvoiceQueueable(List<Id> peIds) {
        this(peIds, 0);
    }

    private ProgramEnrollmentInvoiceQueueable(List<Id> peIds, Integer retry) {
        this.peIds = peIds;
        this.retry = retry;
    }

    public void execute(QueueableContext context) {
        System.debug('=== ProgramEnrollmentInvoiceQueueable START (retry ' + retry + ') ===');

        Integer maxRetries = 10;
        Boolean allReady = true;
        List<Id> toGenerate = new List<Id>();
        Set<Id> alreadyHasInvoice = new Set<Id>();

        for (Id peId : peIds) {
            try {
                // If an invoice file already exists, do not generate again.
                Boolean hasInvoice = [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :peId
                      AND ContentDocument.FileType = 'PDF'
                      AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
                ] > 0;
                if (hasInvoice) {
                    alreadyHasInvoice.add(peId);
                    System.debug('PE ' + peId + ' → invoice already exists; skipping generation.');
                    continue;
                }

                // -------------------------------
                // 1) Determine readiness
                // -------------------------------

                // A) Expected = # of Term Enrollments
                Integer expectedCount = [
                    SELECT COUNT()
                    FROM Term_Enrollment__c
                    WHERE Program_Enrollment__c = :peId
                ];

                // B) Actual = # of Course Enrollments tied to Term Enrollments of this PE
                Integer actualCount = [
                    SELECT COUNT()
                    FROM hed__Course_Enrollment__c
                    WHERE Term_Enrollment__r.Program_Enrollment__c = :peId
                ];

                // Readiness for invoice generation is based on enrollments only.
                // (Student email readiness is handled separately in ProgramEnrollmentStudentEmailQueueable.)
                Boolean isReady = (expectedCount > 0) && (actualCount >= expectedCount);

                System.debug('PE ' + peId + 
                             ' → TermEnrollments=' + expectedCount +
                             ', CourseEnrollments=' + actualCount + 
                             ', isReady=' + isReady);

                if (!isReady) {
                    allReady = false;
                } else {
                    toGenerate.add(peId);
                }

            } catch (Exception e) {
                System.debug('Error while checking readiness for PE ' + peId + ': ' + e.getMessage());
                allReady = false;
            }
        }

        // Retry if not ready and retry limit not hit.
        // In tests, we avoid enqueuing a new async job to prevent
        // deep recursion / maximum stack depth issues.
        if (!allReady && retry < maxRetries) {
            System.debug('Not ready. ' +
                         (Test.isRunningTest()
                             ? 'Skipping re-queue in test context.'
                             : 'Re-queueing for retry #' + (retry + 1)));

            if (!Test.isRunningTest()) {
                System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(peIds, retry + 1));
            }
            return;
        }

        // Ready → Generate invoice PDFs in Batch (getContentAsPDF is supported in Batch execute, not in Queueable in prod).
        System.debug('All records ready. Submitting invoice batch...');
        if (!toGenerate.isEmpty()) {
            if (Test.isRunningTest()) {
                // In test, run PDF generation inline so we don't depend on batch async; then skip student email chain.
                for (Id peId : toGenerate) {
                    try {
                        ProgramEnrollmentInvoiceController.generateAttachAndEmail(peId);
                    } catch (Exception e) {
                        System.debug('Error generating invoice for PE ' + peId + ': ' + e.getMessage());
                    }
                }
            } else {
                Database.executeBatch(new ProgramEnrollmentInvoiceBatch(toGenerate), 1);
            }
        }

        // Chain the student confirmation send attempt even if the invoice already existed.
        // The student email queueable will wait until both invoice + responses PDFs exist and dedupe if already sent.
        if (!Test.isRunningTest() && !peIds.isEmpty()) {
            System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(peIds));
        }

        System.debug('=== ProgramEnrollmentInvoiceQueueable COMPLETE ===');
    }
}