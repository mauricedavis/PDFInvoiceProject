/**
 * Generates invoice PDFs in Batch execute context so getContentAsPDF() is supported
 * (it is not reliable in Queueable in production). When done, chains student confirmation email.
 */
public with sharing class ProgramEnrollmentInvoiceBatch implements Database.Batchable<Id>, Database.AllowsCallouts {

    private List<Id> peIds;

    public ProgramEnrollmentInvoiceBatch(List<Id> peIds) {
        this.peIds = (peIds != null && !peIds.isEmpty()) ? new List<Id>(peIds) : new List<Id>();
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        return peIds;
    }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        for (Id peId : scope) {
            try {
                ProgramEnrollmentInvoiceController.generateAttachAndEmail(peId);
            } catch (Exception e) {
                System.debug('ProgramEnrollmentInvoiceBatch execute for ' + peId + ': ' + e.getTypeName() + ' - ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!Test.isRunningTest() && !peIds.isEmpty()) {
            System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(peIds));
        }
    }
}
