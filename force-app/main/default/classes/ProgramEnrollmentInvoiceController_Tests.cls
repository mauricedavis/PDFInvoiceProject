@IsTest
private class ProgramEnrollmentInvoiceController_Tests {

    @IsTest
    static void triggerSkipsInTestContext() {
        Account program = new Account(Name='MS in Implementation Science');
        insert program;

        Contact student = new Contact(
            LastName='Student', FirstName='Alex', Email='alex@example.edu'
        );
        insert student;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Contact__c = student.Id,
            hed__Account__c = program.Id,
            hed__Enrollment_Status__c = 'Pending Payment'
        );

        Test.startTest();
        insert pe;
        Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(
            pe.Id,
            new List<String>{ 'test@example.edu' }
        );
        Test.stopTest();

        System.assertEquals(null, cvId, 'PDF generation should be skipped in test context');
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id
        ];
        System.assertEquals(0, links.size(),
            'No ContentDocumentLink should be created in test context'
        );
    }
}