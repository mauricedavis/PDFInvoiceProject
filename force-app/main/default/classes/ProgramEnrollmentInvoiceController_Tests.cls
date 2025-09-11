@IsTest
private class ProgramEnrollmentInvoiceController_Tests {

    private static void putProgramOnIfFieldExists(SObject rec, Id programId) {
        Schema.DescribeSObjectResult d = rec.getSObjectType().getDescribe();
        if (d.fields.getMap().containsKey('hed__Account__c')) {
            rec.put('hed__Account__c', programId);
        }
    }

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
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id
        ];
        System.assertEquals(0, links.size(),
            'Trigger should skip VF generation in test context'
        );
    }
}