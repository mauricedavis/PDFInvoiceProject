@IsTest
private class PaymentReceivedEmailInvocable_Tests {

    @IsTest
    static void sendsWhenImplementationScienceProgram() {
        Account acct = new Account(Name = 'Online Certificate in Implementation Science');
        insert acct;

        Contact c = new Contact(FirstName = 'Jamie', LastName = 'Learner', Email = 'jamie.learner@example.com');
        insert c;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        Opportunity opp = new Opportunity(
            Name = 'Term payment test',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acct.Id
        );
        insert opp;

        PaymentReceivedEmailInvocable.Request req = new PaymentReceivedEmailInvocable.Request();
        req.opportunityId = opp.Id;
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        PaymentReceivedEmailInvocable.sendPaymentConfirmation(
            new List<PaymentReceivedEmailInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(
            1,
            PaymentReceivedEmailInvocable.lastBuiltEmailCountForTest,
            'Expected one payment confirmation email to be built for Implementation Science program.'
        );
    }

    @IsTest
    static void skipsWhenNotImplementationScienceProgram() {
        Account acct = new Account(Name = 'Some Other Nursing Program');
        insert acct;

        Contact c = new Contact(FirstName = 'Alex', LastName = 'Student', Email = 'alex@example.com');
        insert c;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        Opportunity opp = new Opportunity(
            Name = 'Other opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acct.Id
        );
        insert opp;

        PaymentReceivedEmailInvocable.Request req = new PaymentReceivedEmailInvocable.Request();
        req.opportunityId = opp.Id;
        req.programEnrollmentId = pe.Id;

        Integer emailsBefore = Limits.getEmailInvocations();
        Test.startTest();
        PaymentReceivedEmailInvocable.sendPaymentConfirmation(
            new List<PaymentReceivedEmailInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(
            emailsBefore,
            Limits.getEmailInvocations(),
            'Expected no email when Account name does not contain IMPLEMENTATION SCIENCE.'
        );
    }

    @IsTest
    static void handlesNullAndEmptyRequests() {
        Test.startTest();
        PaymentReceivedEmailInvocable.sendPaymentConfirmation(null);
        PaymentReceivedEmailInvocable.sendPaymentConfirmation(
            new List<PaymentReceivedEmailInvocable.Request>()
        );
        PaymentReceivedEmailInvocable.sendPaymentConfirmation(
            new List<PaymentReceivedEmailInvocable.Request>{ new PaymentReceivedEmailInvocable.Request() }
        );
        Test.stopTest();
        System.assert(true, 'Handled null/empty safely.');
    }
}
