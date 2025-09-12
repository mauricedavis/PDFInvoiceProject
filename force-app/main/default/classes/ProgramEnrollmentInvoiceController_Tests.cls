@IsTest
private class ProgramEnrollmentInvoiceController_Tests {

    // Set hed__Account__c if that field exists on the given record type
    private static void putProgramOnIfFieldExists(SObject rec, Id programId) {
        Schema.DescribeSObjectResult d = rec.getSObjectType().getDescribe();
        if (d.fields.getMap().containsKey('hed__Account__c')) {
            rec.put('hed__Account__c', programId);
        }
    }

    @IsTest
    static void createsPdfAndEmails() {
        // Program (Account) + Student
        Account program = new Account(Name='MS in Implementation Science'); insert program;
        Contact student = new Contact(LastName='Student', FirstName='Alex', Email='alex@example.edu'); insert student;

        // Program Enrollment
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Contact__c = student.Id,
            hed__Account__c = program.Id,
            hed__Enrollment_Status__c = 'Pending Payment'
        );
        insert pe;

        // Term
        hed__Term__c term = new hed__Term__c(Name='Spring 2028');
        putProgramOnIfFieldExists(term, program.Id);
        insert term;

        // Course
        hed__Course__c course = new hed__Course__c(Name='IMS241 Study Designs');
        putProgramOnIfFieldExists(course, program.Id);
        insert course;

        // Offering
        hed__Course_Offering__c offering = new hed__Course_Offering__c(
            Name='IMS241 Spring 2028',
            hed__Course__c = course.Id,
            hed__Term__c = term.Id,
            hed__Start_Date__c = Date.newInstance(2028,3,1)
        );
        putProgramOnIfFieldExists(offering, program.Id);
        insert offering;

        // Course Connection
        hed__Course_Enrollment__c ce = new hed__Course_Enrollment__c(
            hed__Program_Enrollment__c = pe.Id,
            hed__Course_Offering__c   = offering.Id,
            hed__Status__c            = 'Pending Payment',
            Role__c                   = 'Learner'
        );
        putProgramOnIfFieldExists(ce, program.Id);
        insert ce;

        Test.startTest();
        Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(
            pe.Id,
            new List<String>{ 'bursar@example.edu' }
        );
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion Id should be returned');
        ContentDocumentLink cdl = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id LIMIT 1
        ];
        System.assert(cdl != null, 'Invoice PDF should be linked to the Program Enrollment');
    }
}