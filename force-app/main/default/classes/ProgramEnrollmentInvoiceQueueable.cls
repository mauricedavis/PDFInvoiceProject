/**
 * without sharing: Term/Course Enrollment counts and ContentDocument visibility for integration users.
 */
public without sharing class ProgramEnrollmentInvoiceQueueable implements Queueable, Database.AllowsCallouts {

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
                Boolean hasInvoice = [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :peId
                      AND ContentDocument.FileType = 'PDF'
                      AND (ContentDocument.Title LIKE 'Invoice_%' OR ContentDocument.Title LIKE '%Invoice%')
                ] > 0;
                if (hasInvoice) {
                    if (ProgramEnrollmentInvoiceController.isProgramEnrollmentInvoiceStale(peId)) {
                        ProgramEnrollmentInvoiceController.deleteGeneratedInvoiceContentDocuments(peId);
                        System.debug('PE ' + peId + ' → stale invoice vs Course Connections; removed for regeneration.');
                    } else {
                        alreadyHasInvoice.add(peId);
                        System.debug('PE ' + peId + ' → invoice already exists; skipping generation.');
                        continue;
                    }
                }

                // -------------------------------
                // 1) Determine readiness
                // -------------------------------

                Boolean isReady = ProgramEnrollmentInvoiceController.isReadyForInvoiceGeneration(peId);
                Integer termEnrollmentCount = [
                    SELECT COUNT()
                    FROM Term_Enrollment__c
                    WHERE Program_Enrollment__c = :peId
                ];
                Integer actualCount = ProgramEnrollmentInvoiceController.countCourseConnectionsForProgramEnrollment(peId);

                System.debug('PE ' + peId + 
                             ' → TermEnrollments=' + termEnrollmentCount +
                             ', CourseConnections=' + actualCount + 
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
        // Do NOT enqueue student email here when batch runs: the first student queueable often fired before the
        // invoice PDF existed and exhausted retries. Batch.finish chains student email for ALL peIds (see Batch ctor).
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
                Database.executeBatch(new ProgramEnrollmentInvoiceBatch(toGenerate, peIds), 1);
            }
        } else if (!Test.isRunningTest() && !peIds.isEmpty()) {
            // Every PE already had an invoice PDF — no batch. Chain student email directly.
            System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(peIds));
        }

        System.debug('=== ProgramEnrollmentInvoiceQueueable COMPLETE ===');
    }
}