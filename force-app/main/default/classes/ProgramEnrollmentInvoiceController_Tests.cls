@IsTest
private class ProgramEnrollmentInvoiceController_Tests {

    // Helper: set hed__Account__c dynamically on any sObject if that field exists
    private static void setProgramAccountIfPresent(SObject sobj, Id accountId) {
        if (Schema.sObjectType.getDescribe().fields.getMap().containsKey('hed__Account__c')) {
            try { sobj.put('hed__Account__c', accountId); } catch (Exception e) { /* ignore if not applicable */ }
        } else {
            // Field map per-object (Term, Course, Offering) when using strongly typed sobjects:
            // use describe on the specific object to avoid false negatives with the generic map above
            Schema.DescribeSObjectResult d = sobj.getSObjectType().getDescribe();
            if (d.fields.getMap().containsKey('hed__Account__c')) sobj.put('hed__Account__c', accountId);
        }
    }

    @IsTest
    static void createsPdfAndEmails() {
        // Program (Account) and Student
        Account program = new Account(Name='MS in Implementation Science'); insert program;
        Contact student = new Contact(LastName='Student', FirstName='Alex', Email='alex@example.edu'); insert student;

        // Program Enrollment (requires Contact + Account)
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Contact__c = student.Id,
            hed__Account__c = program.Id,
            hed__Enrollment_Status__c = 'Pending Payment'
        );
        insert pe;

        // Term (some orgs require hed__Account__c)
        hed__Term__c term = new hed__Term__c(Name='Spring 2028');
        setProgramAccountIfPresent(term, program.Id);
        insert term;

        // Course (some orgs require hed__Account__c)
        hed__Course__c course = new hed__Course__c(Name='IMS241 Study Designs');
        setProgramAccountIfPresent(course, program.Id);
        insert course;

        // Course Offering (some orgs require hed__Account__c)
        hed__Course_Offering__c offering = new hed__Course_Offering__c(
            Name='IMS241 Spring 2028',
            hed__Course__c = course.Id,
            hed__Term__c = term.Id,
            hed__Start_Date__c = Date.newInstance(2028,3,1)
        );
        setProgramAccountIfPresent(offering, program.Id);
        insert offering;

        // Course Connection (do not set formula fields)
        hed__Course_Enrollment__c ce = new hed__Course_Enrollment__c(
            hed__Program_Enrollment__c = pe.Id,
            hed__Course_Offering__c = offering.Id,
            hed__Status__c = 'Pending Payment',
            Role__c = 'Learner'
        );
        // Some customers add a required hed__Account__c to Course Enrollment too:
        setProgramAccountIfPresent(ce, program.Id);
        insert ce;

        Test.startTest();
        Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id, new List<String>{'bursar@example.edu'});
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion Id should be returned');
        ContentDocumentLink cdl = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id LIMIT 1];
        System.assert(cdl != null, 'Invoice PDF should be linked to the Program Enrollment');
    }
}