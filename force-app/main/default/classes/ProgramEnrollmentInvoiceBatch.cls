/**
 * Generates invoice PDFs in Batch execute context so getContentAsPDF() is supported
 * (it is not reliable in Queueable in production). When done, chains student confirmation email.
 *
 * without sharing: invoice VF/controller need Term/Course Enrollment and PE data visible to automation.
 *
 * scopeIds: PEs that still need invoice PDF generation.
 * chainStudentEmailPeIds: ALL PEs from the original queueable request (including those that already had
 * an invoice) so every enrollee still gets the student confirmation pass after batch completes.
 */
public without sharing class ProgramEnrollmentInvoiceBatch implements Database.Batchable<Id>, Database.AllowsCallouts {

    private final List<Id> scopeIds;
    private final List<Id> chainStudentEmailPeIds;

    public ProgramEnrollmentInvoiceBatch(List<Id> peIdsToGenerate) {
        this(peIdsToGenerate, peIdsToGenerate);
    }

    public ProgramEnrollmentInvoiceBatch(List<Id> peIdsToGenerate, List<Id> allPeIdsForStudentEmailChain) {
        this.scopeIds = (peIdsToGenerate != null) ? new List<Id>(peIdsToGenerate) : new List<Id>();
        if (allPeIdsForStudentEmailChain != null && !allPeIdsForStudentEmailChain.isEmpty()) {
            this.chainStudentEmailPeIds = new List<Id>(allPeIdsForStudentEmailChain);
        } else {
            this.chainStudentEmailPeIds = new List<Id>(this.scopeIds);
        }
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        return scopeIds;
    }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        for (Id peId : scope) {
            try {
                ProgramEnrollmentInvoiceController.generateAttachAndEmailForBatch(peId);
            } catch (Exception e) {
                System.debug('ProgramEnrollmentInvoiceBatch execute for ' + peId + ': ' + e.getTypeName() + ' - ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!Test.isRunningTest() && !chainStudentEmailPeIds.isEmpty()) {
            System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(chainStudentEmailPeIds));
        }
    }
}
