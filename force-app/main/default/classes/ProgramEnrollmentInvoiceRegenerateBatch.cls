/**
 * Regenerates invoice PDF(s) in Batch execute (getContentAsPDF). Does not chain student email.
 */
public with sharing class ProgramEnrollmentInvoiceRegenerateBatch implements Database.Batchable<Id>, Database.AllowsCallouts {

    private List<Id> peIds;

    public ProgramEnrollmentInvoiceRegenerateBatch(List<Id> peIds) {
        this.peIds = (peIds != null && !peIds.isEmpty()) ? new List<Id>(peIds) : new List<Id>();
    }

    public Iterable<Id> start(Database.BatchableContext bc) {
        return peIds;
    }

    public void execute(Database.BatchableContext bc, List<Id> scope) {
        for (Id peId : scope) {
            try {
                ProgramEnrollmentInvoiceController.regenerateInvoicePdf(peId);
            } catch (Exception e) {
                System.debug('ProgramEnrollmentInvoiceRegenerateBatch execute for ' + peId + ': ' + e.getTypeName() + ' - ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (peIds.isEmpty()) return;
        try {
            if (Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Regenerate_Invoice__c')) {
                List<SObject> toClear = new List<SObject>();
                for (Id peId : peIds) {
                    SObject pe = Schema.getGlobalDescribe().get('hed__Program_Enrollment__c').newSObject(peId);
                    pe.put('Regenerate_Invoice__c', false);
                    toClear.add(pe);
                }
                update toClear;
            }
        } catch (Exception e) {
            System.debug('ProgramEnrollmentInvoiceRegenerateBatch.finish: ' + e.getMessage());
        }
    }
}
