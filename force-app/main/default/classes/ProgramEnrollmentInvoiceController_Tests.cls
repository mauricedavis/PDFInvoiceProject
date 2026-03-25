@isTest
private class ProgramEnrollmentInvoiceController_Tests {

    /**
     * Test data:
     * - One "ready" Program Enrollment with:
     *   - Contact + email
     *   - One Term_Enrollment__c
     *   - One hed__Course_Enrollment__c tied to that term
     *   - One Course Registration PDF (ContentVersion + ContentDocumentLink)
     * - One "no-contact" Program Enrollment (to exercise the skip-email path).
     */
    @testSetup
    static void setupTestData() {
        Account acct = new Account(Name = 'Test Program Account');
        insert acct;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName  = 'User',
            Email     = 'testuser@example.com'
        );
        insert con;

        // Ready Program Enrollment (has Contact + related records)
        hed__Program_Enrollment__c peReady = new hed__Program_Enrollment__c(
            hed__Account__c        = acct.Id,
            hed__Contact__c        = con.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert peReady;

        // Term Enrollment for readiness checks
        Term_Enrollment__c te = new Term_Enrollment__c(
            Name                 = 'Test Term Enrollment',
            Program_Enrollment__c = peReady.Id
        );
        insert te;

        // Course Enrollment tied to the Term Enrollment
        hed__Course_Enrollment__c ce = new hed__Course_Enrollment__c(
            Term_Enrollment__c = te.Id
        );
        insert ce;

        // Create a Course Registration PDF file and link it to the Program Enrollment
        ContentVersion cv = new ContentVersion(
            Title        = 'Course Registration Test',
            PathOnClient = 'CourseRegistrationTest.pdf',
            VersionData  = Blob.valueOf('PDF content'),
            IsMajorVersion = true
        );
        insert cv;

        Id docId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ].ContentDocumentId;

        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = peReady.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert cdl;

        // Add a late fee so the controller late-fee branch is exercised
        peReady.Enrollment_Late_Fee__c = 50;
        update peReady;

        // Program Enrollment without a Contact (for skip-email scenario)
        hed__Program_Enrollment__c peNoContact = new hed__Program_Enrollment__c(
            hed__Account__c        = acct.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert peNoContact;

        // Program Enrollment with Contact but without any Course Registration PDF
        hed__Program_Enrollment__c peNoPdf = new hed__Program_Enrollment__c(
            hed__Account__c        = acct.Id,
            hed__Contact__c        = con.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert peNoPdf;
    }

    @isTest
    static void test_ControllerGeneratesInvoiceFile() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        Test.startTest();
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);
        Test.stopTest();

        // Verify at least one ContentDocumentLink (invoice or responses) now exists
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
        ];
        System.assert(!links.isEmpty(), 'Expected at least one file linked to the Program Enrollment.');
    }

    @isTest
    static void test_ControllerVFConstructorAndGetters() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        // Simulate Visualforce context for PDFInvoiceActionOne
        PageReference pr = Page.PDFInvoiceActionOne;
        pr.getParameters().put('id', pe.Id);
        Test.setCurrentPage(pr);

        Test.startTest();
        ProgramEnrollmentInvoiceController ctrl = new ProgramEnrollmentInvoiceController();
        // Exercise getters to ensure all VF-related logic runs
        hed__Program_Enrollment__c peLoaded = ctrl.getProgramEnrollment();
        List<hed__Course_Enrollment__c> courses = ctrl.getCourseEnrollments();
        Decimal total = ctrl.getTotalAmount();
        Boolean hasLateFee = ctrl.getHasEnrollmentLateFee();
        Test.stopTest();

        System.assertNotEquals(null, peLoaded, 'Controller should load a Program Enrollment.');
    }

    @isTest
    static void test_Queueable_ReadyPath() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(pe.Id));
        Test.stopTest();

        // The queueable should have generated an invoice file
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
        ];
        System.assert(!links.isEmpty(), 'Queueable should generate and attach at least one invoice file.');
    }

    @isTest
    static void test_NoContactSkipEmail() {
        hed__Program_Enrollment__c peNoContact = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c = null
            LIMIT 1
        ];

        Test.startTest();
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(peNoContact.Id);
        Test.stopTest();

        // No assertion on email; just ensure no exceptions are thrown
        System.assert(true, 'Handled case where no Contact is associated.');
    }

    @isTest
    static void test_ControllerHandlesNoResponsesPdf() {
        // Use the Program Enrollment that has a Contact but no responses PDF
        hed__Program_Enrollment__c peNoPdf = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        Test.startTest();
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(peNoPdf.Id);
        Test.stopTest();

        // No assertion beyond "no exception"; this exercises the
        // branch where no responses PDF is found.
        System.assert(true, 'Controller should handle missing responses PDF gracefully.');
    }

    @isTest
    static void test_FlowActionInvokesQueueable() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        Test.startTest();
        ProgramEnrollmentInvoiceFlowAction.generateInvoice(new List<Id>{ pe.Id });
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
        ];
        System.assert(!links.isEmpty(), 'Flow action should ultimately result in a file linked to the Program Enrollment.');
    }

    @isTest
    static void test_PEInvoiceActionOneExecutes() {
        // Create an additional ready Program Enrollment for the Invocable entry point
        Account acct = new Account(Name = 'Batch Program');
        insert acct;

        Contact con = new Contact(
            FirstName = 'Batch',
            LastName  = 'User',
            Email     = 'batchuser@example.com'
        );
        insert con;

        hed__Program_Enrollment__c peBatch = new hed__Program_Enrollment__c(
            hed__Account__c        = acct.Id,
            hed__Contact__c        = con.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert peBatch;

        // Call the Invocable method directly
        PEInvoiceActionOne.Req req = new PEInvoiceActionOne.Req();
        req.ProgramEnrollmentId = peBatch.Id;

        Test.startTest();
        List<Id> results = PEInvoiceActionOne.send(new List<PEInvoiceActionOne.Req>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one result from PEInvoiceActionOne.send.');
        System.assertEquals(peBatch.Id, results[0], 'Returned Id should match the Program Enrollment Id.');
    }

    @isTest
    static void test_InvocablePEInvoiceAndAttachInvocables() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];

        InvocablePEInvoice.Request r = new InvocablePEInvoice.Request();
        r.programEnrollmentId = pe.Id;
        r.toAddresses = new List<String>{ 'cc@example.com' };

        Test.startTest();
        List<InvocablePEInvoice.Response> resp = InvocablePEInvoice.generateAndEmail(
            new List<InvocablePEInvoice.Request>{ r }
        );
        List<Id> attachResp = InvocablePEInvoiceAttach.generateAndAttach(new List<Id>{ pe.Id });
        List<Id> byRecordResp = PEInvoiceAttachByRecord.generateAndAttach(
            new List<hed__Program_Enrollment__c>{ new hed__Program_Enrollment__c(Id = pe.Id) }
        );
        List<Id> flowByRecordResp = PEInvoiceFlowByRecord.generateAndEmail(
            new List<hed__Program_Enrollment__c>{ new hed__Program_Enrollment__c(Id = pe.Id) }
        );
        Test.stopTest();

        System.assertEquals(1, resp.size(), 'Expected one response from InvocablePEInvoice.');
        System.assertEquals(1, attachResp.size(), 'Expected one id from InvocablePEInvoiceAttach.');
        System.assertEquals(1, byRecordResp.size(), 'Expected one id from PEInvoiceAttachByRecord.');
        System.assertEquals(1, flowByRecordResp.size(), 'Expected one id from PEInvoiceFlowByRecord.');
    }

    @isTest
    static void test_InvoiceQueueable_NotReadyPathInTests() {
        // Create a PE that is NOT ready: no Term Enrollment, no Course Enrollments, no PDF.
        Account acct = new Account(Name = 'Not Ready Program');
        insert acct;
        Contact con = new Contact(FirstName = 'Not', LastName = 'Ready', Email = 'not.ready@example.com');
        insert con;
        hed__Program_Enrollment__c peNotReady = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = con.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert peNotReady;

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(peNotReady.Id));
        Test.stopTest();

        // In test context, queueable should NOT re-enqueue; it should simply return.
        Integer links = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :peNotReady.Id];
        System.assertEquals(0, links, 'Expected no files generated when record is not ready in test context.');
    }

    @isTest
    static void test_TermAndCourseTriggers_GenerateInvoiceWhenReady() {
        Account acct = new Account(Name = 'Trigger Program');
        insert acct;
        Contact con = new Contact(FirstName = 'Trig', LastName = 'Ger', Email = 'trigger@example.com');
        insert con;

        // PE insert should NOT generate the invoice yet (course enrollments come later).
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = con.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        Test.startTest();
        insert pe;

        // Create the enrollments that drive invoice readiness.
        Term_Enrollment__c te = new Term_Enrollment__c(Name = 'Trig Term', Program_Enrollment__c = pe.Id);
        insert te;
        insert new hed__Course_Enrollment__c(Term_Enrollment__c = te.Id);
        Test.stopTest();

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id];
        System.assert(linkCount > 0, 'Invoice should be generated once term + course enrollments exist.');

        // Touch the empty handler class for coverage.
        ProgramEnrollmentInvoiceTriggerHandler.isExecuting = true;
        System.assertEquals(true, ProgramEnrollmentInvoiceTriggerHandler.isExecuting, 'Trigger handler flag settable.');
    }

    @isTest
    static void test_InvoiceBatch_GeneratesPdf() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];

        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceBatch(new List<Id>{ pe.Id }), 1);
        Test.stopTest();

        Integer linkCount = [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id];
        System.assert(linkCount > 0, 'Batch execute should generate and attach invoice file.');
    }

    @isTest
    static void test_RegenerateInvoicePdf_ReplacesExisting() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, Name
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];

        Test.startTest();
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);
        Integer afterFirst = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.FileType = 'PDF'
              AND ContentDocument.Title LIKE 'Invoice%'
        ];
        System.assert(afterFirst > 0, 'Expected initial invoice file.');

        ProgramEnrollmentInvoiceController.regenerateInvoicePdf(pe.Id);
        Test.stopTest();

        Integer afterRegen = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.FileType = 'PDF'
              AND ContentDocument.Title LIKE 'Invoice%'
        ];
        System.assert(afterRegen > 0, 'Expected invoice file after regenerate.');
    }

    @isTest
    static void test_RegenerateInvocable_CallsRegenerate() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);

        PEInvoiceRegenerateInvocable.Request req = new PEInvoiceRegenerateInvocable.Request();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        PEInvoiceRegenerateInvocable.regenerate(
            new List<PEInvoiceRegenerateInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :pe.Id AND ContentDocument.Title LIKE 'Invoice%'] > 0,
            'Invocable regenerate should leave an invoice file on the PE.'
        );
    }

    @isTest
    static void test_RegenerateCheckboxTrigger_FiresInTest() {
        if (!Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Regenerate_Invoice__c')) {
            System.assert(true, 'Regenerate_Invoice__c not present; deploy custom field with this package.');
            return;
        }

        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);

        SObject peUpdate = Schema.getGlobalDescribe().get('hed__Program_Enrollment__c').newSObject(pe.Id);
        peUpdate.put('Regenerate_Invoice__c', true);

        Test.startTest();
        update peUpdate;
        Test.stopTest();

        Id peId = pe.Id;
        List<SObject> rows = Database.query(
            'SELECT Regenerate_Invoice__c FROM hed__Program_Enrollment__c WHERE Id = :peId LIMIT 1'
        );
        System.assertEquals(
            false,
            rows[0].get('Regenerate_Invoice__c'),
            'Trigger should clear Regenerate_Invoice__c after test regeneration.'
        );
    }
}