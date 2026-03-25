/**
 * When Regenerate_Invoice__c is checked on save, enqueue async regeneration and clear the flag when batch finishes.
 */
trigger ProgramEnrollmentRegenerateInvoiceTrigger on hed__Program_Enrollment__c (after update) {

    if (!Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Regenerate_Invoice__c')) {
        return;
    }

    if (TriggerHandlerHelper.isAlreadyRunning('ProgramEnrollmentRegenerateInvoiceTrigger')) {
        return;
    }
    TriggerHandlerHelper.markRunning('ProgramEnrollmentRegenerateInvoiceTrigger');

    List<Id> peIds = new List<Id>();
    for (hed__Program_Enrollment__c pe : Trigger.new) {
        SObject oldPe = Trigger.oldMap.get(pe.Id);
        Object nowVal = pe.get('Regenerate_Invoice__c');
        Object oldVal = oldPe != null ? oldPe.get('Regenerate_Invoice__c') : null;
        Boolean nowOn = (nowVal == true);
        Boolean wasOn = (oldVal == true);
        if (nowOn && !wasOn) {
            peIds.add(pe.Id);
        }
    }

    if (peIds.isEmpty()) return;

    if (Test.isRunningTest()) {
        for (Id peId : peIds) {
            ProgramEnrollmentInvoiceController.regenerateInvoicePdf(peId);
        }
        try {
            if (Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Regenerate_Invoice__c')) {
                List<SObject> toClear = new List<SObject>();
                for (Id peId : peIds) {
                    SObject row = Schema.getGlobalDescribe().get('hed__Program_Enrollment__c').newSObject(peId);
                    row.put('Regenerate_Invoice__c', false);
                    toClear.add(row);
                }
                update toClear;
            }
        } catch (Exception ignore) { }
        return;
    }

    Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(peIds), 1);
}
