trigger OpportunityTermPaymentDuplicateTrigger on Opportunity (before insert) {
    TermPaymentOpportunityDuplicateBlocker.beforeInsert(Trigger.new);
}
