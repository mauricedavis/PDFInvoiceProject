@IsTest
private class ProgramEnrollmentInvoiceController_Tests {
    @IsTest
    static void createsPdfAndEmails() {
        Account program = new Account(Name='MS in Implementation Science'); insert program;
        Contact student = new Contact(LastName='Student', FirstName='Alex', Email='alex@example.edu'); insert student;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            Name='PE-0001',
            hed__Contact__c = student.Id,
            hed__Account__c = program.Id,
            hed__Enrollment_Status__c = 'Pending Payment'
        ); insert pe;

        hed__Term__c term = new hed__Term__c(Name='Spring 2028'); insert term;
        hed__Course__c course = new hed__Course__c(Name='IMS241 Study Designs'); insert course;

        hed__Course_Offering__c offering = new hed__Course_Offering__c(
            Name='IMS241 Spring 2028',
            hed__Course__c = course.Id,
            hed__Start_Date__c = Date.newInstance(2028,3,1)
        ); insert offering;

        hed__Course_Enrollment__c ce = new hed__Course_Enrollment__c(
            Name='CC-1202',
            hed__Program_Enrollment__c = pe.Id,
            hed__Course__c = course.Id,
            hed__Course_Offering__c = offering.Id,
            hed__Term__c = term.Id,
            hed__Role__c = 'Learner',
            hed__Status__c = 'Pending Payment',
            Course_Fee__c = 2900
        ); insert ce;

        Test.startTest();
        Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id, new List<String>{'bursar@example.edu'});
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion Id should be returned');
        ContentDocumentLink cdl = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id LIMIT 1];
        System.assert(cdl != null, 'Invoice PDF should be linked to the Program Enrollment');
    }
}