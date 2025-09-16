/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
trigger dlrs_hed_Plan_RequirementTrigger on hed__Plan_Requirement__c
    (before delete, before insert, before update, after delete, after insert, after undelete, after update)
{
    dlrs.RollupService.triggerHandler(hed__Plan_Requirement__c.SObjectType);
}