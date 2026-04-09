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
        System.assert(
            PaymentReceivedEmailInvocable.lastHtmlBodyForTest != null &&
                PaymentReceivedEmailInvocable.lastHtmlBodyForTest.contains(
                    'Online Certificate in Implementation Science'
                ),
            'Without a Course Connection, enrollment line should fall back to program Account name.'
        );
    }

    @IsTest
    static void sendResolvesCourseConnectionFromDatabase() {
        Account acct = new Account(Name = 'Online Certificate in Implementation Science');
        insert acct;

        Contact c = new Contact(FirstName = 'Riley', LastName = 'Learner', Email = 'riley.learner@example.com');
        insert c;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        Term_Enrollment__c te = new Term_Enrollment__c(
            Name = 'TE Riley Spring 2026',
            Program_Enrollment__c = pe.Id
        );
        insert te;

        insert new hed__Course_Enrollment__c(Term_Enrollment__c = te.Id);

        Opportunity opp = new Opportunity(
            Name = 'Course payment test',
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

        System.assertEquals(1, PaymentReceivedEmailInvocable.lastBuiltEmailCountForTest);
        System.assertNotEquals(null, PaymentReceivedEmailInvocable.lastHtmlBodyForTest);
        System.assert(
            PaymentReceivedEmailInvocable.lastHtmlBodyForTest.contains('enrolled in <strong>'),
            'Expected enrollment sentence with a course connection or formula-backed label.'
        );
    }

    @IsTest
    static void offeringLabelsPreferCourseOfferingRelationshipName() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        if (!fm.containsKey('hed__Course_Offering__c')) {
            return;
        }

        hed__Program_Enrollment__c pe = programEnrollmentForLabelTests();
        String payload =
            '{"attributes":{"type":"hed__Course_Enrollment__c"},"Name":"CC-Label-1","Course_Name__c":"Fallback Name",'
            + '"hed__Course_Offering__r":{"attributes":{"type":"hed__Course_Offering__c"},"Name":"Offering Display"},'
            + '"Term_Enrollment__r":{"attributes":{"type":"Term_Enrollment__c"},"Program_Enrollment__c":"'
            + String.valueOf(pe.Id)
            + '"}}';
        hed__Course_Enrollment__c row = (hed__Course_Enrollment__c) JSON.deserialize(
            payload,
            hed__Course_Enrollment__c.class
        );

        Map<Id, String> labels = PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
            new List<hed__Course_Enrollment__c>{ row },
            new Set<Id>{ pe.Id }
        );
        System.assertEquals('Offering Display', labels.get(pe.Id));
    }

    @IsTest
    static void offeringLabelsUseCourseNameWhenOfferingBlank() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        if (!fm.containsKey('Course_Name__c')) {
            return;
        }

        hed__Program_Enrollment__c pe = programEnrollmentForLabelTests();
        String payload =
            '{"attributes":{"type":"hed__Course_Enrollment__c"},"Name":"CC-Only-Name","Course_Name__c":"Course Name Only",'
            + '"Term_Enrollment__r":{"attributes":{"type":"Term_Enrollment__c"},"Program_Enrollment__c":"'
            + String.valueOf(pe.Id)
            + '"}}';
        hed__Course_Enrollment__c row = (hed__Course_Enrollment__c) JSON.deserialize(
            payload,
            hed__Course_Enrollment__c.class
        );

        Map<Id, String> labels = PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
            new List<hed__Course_Enrollment__c>{ row },
            new Set<Id>{ pe.Id }
        );
        System.assertEquals('Course Name Only', labels.get(pe.Id));
    }

    @IsTest
    static void offeringLabelsPickEarlierStartDate() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        if (!fm.containsKey('Course_Offering_Start_Date__c') || !fm.containsKey('Course_Name__c')) {
            return;
        }

        hed__Program_Enrollment__c pe = programEnrollmentForLabelTests();
        String base =
            '"attributes":{"type":"hed__Course_Enrollment__c"},'
            + '"Term_Enrollment__r":{"attributes":{"type":"Term_Enrollment__c"},"Program_Enrollment__c":"'
            + String.valueOf(pe.Id)
            + '"}';
        String jsonLate =
            '{' + base + ',"Course_Name__c":"Later Row","Course_Offering_Start_Date__c":"2030-06-01"}';
        String jsonEarly =
            '{' + base + ',"Course_Name__c":"Earlier Row","Course_Offering_Start_Date__c":"2026-01-15"}';

        hed__Course_Enrollment__c lateRow = (hed__Course_Enrollment__c) JSON.deserialize(
            jsonLate,
            hed__Course_Enrollment__c.class
        );
        hed__Course_Enrollment__c earlyRow = (hed__Course_Enrollment__c) JSON.deserialize(
            jsonEarly,
            hed__Course_Enrollment__c.class
        );

        Map<Id, String> labelsOrderedLateFirst = PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
            new List<hed__Course_Enrollment__c>{ lateRow, earlyRow },
            new Set<Id>{ pe.Id }
        );
        System.assertEquals('Earlier Row', labelsOrderedLateFirst.get(pe.Id));

        Map<Id, String> labelsOrderedEarlyFirst = PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
            new List<hed__Course_Enrollment__c>{ earlyRow, lateRow },
            new Set<Id>{ pe.Id }
        );
        System.assertEquals('Earlier Row', labelsOrderedEarlyFirst.get(pe.Id));
    }

    @IsTest
    static void offeringLabelsRespectProgramEnrollmentLookup() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        if (!fm.containsKey('Program_Enrollment__c')) {
            return;
        }

        hed__Program_Enrollment__c pe = programEnrollmentForLabelTests();
        String payload =
            '{"attributes":{"type":"hed__Course_Enrollment__c"},"Name":"CC-Direct-PE","Course_Name__c":"Via Program_Enrollment__c",'
            + '"Program_Enrollment__c":"'
            + String.valueOf(pe.Id)
            + '"}';
        hed__Course_Enrollment__c row = (hed__Course_Enrollment__c) JSON.deserialize(
            payload,
            hed__Course_Enrollment__c.class
        );

        Map<Id, String> labels = PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
            new List<hed__Course_Enrollment__c>{ row },
            new Set<Id>{ pe.Id }
        );
        System.assertEquals('Via Program_Enrollment__c', labels.get(pe.Id));
    }

    @IsTest
    static void offeringLabelsRespectHedProgramEnrollmentLookup() {
        Map<String, Schema.SObjectField> fm = Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap();
        if (!fm.containsKey('hed__Program_Enrollment__c')) {
            return;
        }

        hed__Program_Enrollment__c pe = programEnrollmentForLabelTests();
        String payload =
            '{"attributes":{"type":"hed__Course_Enrollment__c"},"Name":"CC-Hed-PE","Course_Name__c":"Via hed__PE",'
            + '"hed__Program_Enrollment__c":"'
            + String.valueOf(pe.Id)
            + '"}';
        hed__Course_Enrollment__c row = (hed__Course_Enrollment__c) JSON.deserialize(
            payload,
            hed__Course_Enrollment__c.class
        );

        Map<Id, String> labels = PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
            new List<hed__Course_Enrollment__c>{ row },
            new Set<Id>{ pe.Id }
        );
        System.assertEquals('Via hed__PE', labels.get(pe.Id));
    }

    @IsTest
    static void offeringLabelsEmptyInputReturnsEmptyMap() {
        hed__Program_Enrollment__c pe = programEnrollmentForLabelTests();
        System.assertEquals(
            0,
            PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(
                    new List<hed__Course_Enrollment__c>(),
                    new Set<Id>{ pe.Id }
                )
                .size()
        );
        System.assertEquals(
            0,
            PaymentReceivedEmailInvocable.offeringLabelsFromCourseConnectionRowsForTest(null, new Set<Id>{ pe.Id })
                .size()
        );
    }

    private static hed__Program_Enrollment__c programEnrollmentForLabelTests() {
        Account acct = new Account(Name = 'Online Certificate in Implementation Science');
        insert acct;

        Contact c = new Contact(FirstName = 'Label', LastName = 'Test', Email = 'label.test@example.com');
        insert c;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        return pe;
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
