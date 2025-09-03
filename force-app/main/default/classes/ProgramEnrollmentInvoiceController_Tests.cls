@IsTest
private class ProgramEnrollmentInvoiceController_Tests {

    private static void putProgramOnIfFieldExists(SObject rec, Id programId) {
        Schema.DescribeSObjectResult d = rec.getSObjectType().getDescribe();
        if (d.fields.getMap().containsKey('hed__Account__c')) {
            rec.put('hed__Account__c', programId);
        }
    }

    @IsTest
    static void createsPdfAndEmails() {
        Account program = new Account(Name='MS in Implementation Science'); insert program;
        Contact student = new Contact(LastName='Student', FirstName='Alex', Email='alex@example.edu'); insert student;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Contact__c = student.Id,
            hed__Account__c = program.Id,
            hed__Enrollment_Status__c = 'Pending Payment'
        ); insert pe;

        hed__Term__c term = new hed__Term__c(Name='Spring 2028'); putProgramOnIfFieldExists(term, program.Id); insert term;
        hed__Course__c course = new hed__Course__c(Name='IMS241 Study Designs'); putProgramOnIfFieldExists(course, program.Id); insert course;
        hed__Course_Offering__c offering = new hed__Course_Offering__c(
            Name='IMS241 Spring 2028',
            hed__Course__c = course.Id,
            hed__Term__c = term.Id,
            hed__Start_Date__c = Date.newInstance(2028,3,1)
        ); putProgramOnIfFieldExists(offering, program.Id); insert offering;

        hed__Course_Enrollment__c ce = new hed__Course_Enrollment__c(
            hed__Program_Enrollment__c = pe.Id,
            hed__Course_Offering__c   = offering.Id,
            hed__Status__c            = 'Pending Payment',
            Role__c                   = 'Learner'
        ); putProgramOnIfFieldExists(ce, program.Id); insert ce;

        Test.startTest();
        Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(
            pe.Id, new List<String>{ 'bursar@example.edu' }
        );
        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion Id should be returned');

        // Flags on PE
        hed__Program_Enrollment__c peAfter = [
            SELECT Invoice_Created__c, Invoice_Emailed__c,
                   Invoice_Last_Sent__c, Last_Invoice_ContentVersion_Id__c
            FROM hed__Program_Enrollment__c WHERE Id = :pe.Id
        ];
        System.assertEquals(true, peAfter.Invoice_Created__c, 'Invoice_Created__c should be true');
        System.assertEquals(true, peAfter.Invoice_Emailed__c, 'Invoice_Emailed__c should be true');
        System.assertNotEquals(null, peAfter.Invoice_Last_Sent__c, 'Invoice_Last_Sent__c should be set');
        System.assertNotEquals(null, peAfter.Last_Invoice_ContentVersion_Id__c, 'Last_Invoice_ContentVersion_Id__c should be set');

        // File linked to PE
        ContentDocumentLink cdl = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id LIMIT 1
        ];
        System.assert(cdl != null, 'Invoice PDF should be linked to the Program Enrollment');

        // EmailMessage logged on PE
        EmailMessage em = [
            SELECT Id, RelatedToId, Status, Incoming
            FROM EmailMessage WHERE RelatedToId = :pe.Id LIMIT 1
        ];
        System.assert(em != null, 'EmailMessage should be created and related to Program Enrollment');
        System.assertEquals('3', em.Status, 'EmailMessage should be Sent');
        System.assertEquals(false, em.Incoming, 'EmailMessage should be outgoing');
    }
}