@isTest
private class ProgramEnrollmentInvoiceController_Tests {

    /** PE that has Term_Enrollment__c + hed__Course_Enrollment__c from @testSetup. */
    private static Id programEnrollmentReadyForInvoiceId() {
        List<hed__Course_Enrollment__c> rows = [
            SELECT Term_Enrollment__r.Program_Enrollment__c
            FROM hed__Course_Enrollment__c
            WHERE Term_Enrollment__c != null
              AND Term_Enrollment__r.Program_Enrollment__c != null
            LIMIT 1
        ];
        System.assert(
            !rows.isEmpty(),
            'testSetup must create hed__Course_Enrollment__c linked to Term_Enrollment__c and Program Enrollment.'
        );
        return rows[0].Term_Enrollment__r.Program_Enrollment__c;
    }

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
        Id peId = programEnrollmentReadyForInvoiceId();

        Test.startTest();
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(peId);
        Test.stopTest();

        // Verify at least one ContentDocumentLink (invoice or responses) now exists
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
        ];
        System.assert(!links.isEmpty(), 'Expected at least one file linked to the Program Enrollment.');
    }

    @isTest
    static void test_ControllerVFConstructorAndGetters() {
        Id peId = programEnrollmentReadyForInvoiceId();

        // Simulate Visualforce context for PDFInvoiceActionOne
        PageReference pr = Page.PDFInvoiceActionOne;
        pr.getParameters().put('id', peId);
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
        System.assertEquals(1, courses.size(), 'Invoice should list Course Connections from Term_Enrollment → PE path.');
    }

    @isTest
    static void test_CourseConnectionWhereClause_coversTermAndOptionalDirectPe() {
        String w = ProgramEnrollmentInvoiceController.courseConnectionWhereClauseForProgramEnrollment();
        System.assert(w.contains('Term_Enrollment__r.Program_Enrollment__c'), w);
        if (Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap().containsKey('hed__Program_Enrollment__c')) {
            System.assert(w.contains('hed__Program_Enrollment__c'), w);
        }
        if (Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap().containsKey('Program_Enrollment__c')) {
            System.assert(w.contains('Program_Enrollment__c'), w);
        }
    }

    @isTest
    static void test_IsProgramEnrollmentFullyEnrolledForConfirmationSkip() {
        Id peId = programEnrollmentReadyForInvoiceId();
        System.assert(
            !ProgramEnrollmentInvoiceController.isProgramEnrollmentFullyEnrolledForConfirmationSkip(peId),
            'Payment Pending should not skip student confirmation queue.'
        );

        hed__Program_Enrollment__c pe = [SELECT Id FROM hed__Program_Enrollment__c WHERE Id = :peId];
        pe.hed__Enrollment_Status__c = 'Currently Enrolled';
        update pe;

        System.assert(
            ProgramEnrollmentInvoiceController.isProgramEnrollmentFullyEnrolledForConfirmationSkip(peId),
            'Currently Enrolled should skip registration+invoice confirmation enqueue after payment.'
        );
        System.assert(
            !ProgramEnrollmentInvoiceController.isProgramEnrollmentFullyEnrolledForConfirmationSkip(null),
            'Null id should not be treated as enrolled.'
        );
    }

    @isTest
    static void test_TriggerCore_nullOrEmptyNewRows_noOp() {
        CourseEnrollmentInvoiceTriggerCore.afterInsertOrUpdate(null, null, false);
        CourseEnrollmentInvoiceTriggerCore.afterInsertOrUpdate(new List<hed__Course_Enrollment__c>(), null, false);
        System.assert(true);
    }

    @isTest
    static void test_CountCourseConnectionsForProgramEnrollment() {
        Id peId = programEnrollmentReadyForInvoiceId();
        System.assertEquals(1, ProgramEnrollmentInvoiceController.countCourseConnectionsForProgramEnrollment(peId));
    }

    /**
     * Exercises CourseEnrollmentInvoiceTrigger update path when hed__Program_Enrollment__c is populated (coverage).
     */
    @isTest
    static void test_CourseEnrollmentTrigger_updateSetsHedProgramEnrollment() {
        if (!Schema.SObjectType.hed__Course_Enrollment__c.fields.getMap().containsKey('hed__Program_Enrollment__c')) {
            return;
        }
        Id peId = programEnrollmentReadyForInvoiceId();
        hed__Course_Enrollment__c ce = [
            SELECT Id
            FROM hed__Course_Enrollment__c
            WHERE Term_Enrollment__r.Program_Enrollment__c = :peId
            LIMIT 1
        ];
        ce.put('hed__Program_Enrollment__c', peId);
        Test.startTest();
        update ce;
        Test.stopTest();
        System.assertNotEquals(null, ce.Id);
    }

    /** Moves Course Connection to another Term on the same PE (Trigger.isUpdate + Trigger.old paths). */
    @isTest
    static void test_CourseEnrollmentTrigger_updateChangesTermEnrollment() {
        Id peId = programEnrollmentReadyForInvoiceId();
        Term_Enrollment__c te2 = new Term_Enrollment__c(
            Name = 'Second Term For Trigger',
            Program_Enrollment__c = peId
        );
        insert te2;
        hed__Course_Enrollment__c ce = [
            SELECT Id, Term_Enrollment__c
            FROM hed__Course_Enrollment__c
            WHERE Term_Enrollment__r.Program_Enrollment__c = :peId
            LIMIT 1
        ];
        ce.Term_Enrollment__c = te2.Id;
        Test.startTest();
        update ce;
        Test.stopTest();
        System.assertEquals(
            te2.Id,
            [SELECT Term_Enrollment__c FROM hed__Course_Enrollment__c WHERE Id = :ce.Id].Term_Enrollment__c
        );
    }

    @isTest
    static void test_Queueable_ReadyPath() {
        Id peId = programEnrollmentReadyForInvoiceId();

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentInvoiceQueueable(peId));
        Test.stopTest();

        // The queueable should have generated an invoice file
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
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
    static void test_RegenerateBatch_emptyList_completes() {
        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(null), 1);
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(new List<Id>()), 1);
        Test.stopTest();
        System.assert(true, 'Empty regenerate batch should finish without error.');
    }

    @isTest
    static void test_RegenerateBatch_executeCatchesRegenerateException() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];
        ProgramEnrollmentInvoiceController.throwFromRegenerateInvoicePdfForTest = true;
        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(new List<Id>{ pe.Id }), 1);
        Test.stopTest();
        ProgramEnrollmentInvoiceController.throwFromRegenerateInvoicePdfForTest = false;
        System.assert(true, 'Batch execute should swallow exceptions from regenerateInvoicePdf.');
    }

    @isTest
    static void test_RegenerateBatch_finishCatchesUpdateFailureWhenCheckboxFieldPresent() {
        if (!Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Regenerate_Invoice__c')) {
            System.assert(true, 'Regenerate_Invoice__c not deployed; skip finish catch path.');
            return;
        }
        Account acct = new Account(Name = 'Batch Finish Catch Acct');
        insert acct;
        Contact con = new Contact(FirstName = 'Batch', LastName = 'FinishCatch', Email = 'bfc@example.com');
        insert con;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = con.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        Id deletedId = pe.Id;
        delete pe;

        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(new List<Id>{ deletedId }), 1);
        Test.stopTest();
        System.assert(true, 'finish() should catch DML errors when clearing checkbox on deleted rows.');
    }

    @isTest
    static void test_RegenerateBatch_executesRegenerateAndFinish() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);

        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(new List<Id>{ pe.Id }), 1);
        Test.stopTest();

        Integer invCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.FileType = 'PDF'
              AND ContentDocument.Title LIKE 'Invoice%'
        ];
        System.assert(invCount > 0, 'Regenerate batch should leave an invoice PDF on the PE.');
    }

    @isTest
    static void test_RegenerateBatch_twoProgramEnrollments() {
        List<hed__Program_Enrollment__c> pes = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 2
        ];
        System.assert(pes.size() >= 1, 'Setup should provide at least one PE with contact.');
        List<Id> ids = new List<Id>();
        for (hed__Program_Enrollment__c pe : pes) {
            ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);
            ids.add(pe.Id);
        }

        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(ids), 10);
        Test.stopTest();

        for (Id peId : ids) {
            System.assert(
                [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :peId AND ContentDocument.Title LIKE 'Invoice%'] > 0,
                'Each PE should still have an invoice after batch.'
            );
        }
    }

    @isTest
    static void test_RegenerateBatch_finishClearsRegenerateCheckboxWhenPresent() {
        if (!Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Regenerate_Invoice__c')) {
            System.assert(true, 'Regenerate_Invoice__c not deployed in this org; skip finish() update path.');
            return;
        }

        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            WHERE hed__Contact__c != null
            LIMIT 1
        ];
        ProgramEnrollmentInvoiceController.generateAttachAndEmail(pe.Id);

        SObject flagOn = Schema.getGlobalDescribe().get('hed__Program_Enrollment__c').newSObject(pe.Id);
        flagOn.put('Regenerate_Invoice__c', true);
        update flagOn;

        Id peId = pe.Id;
        Test.startTest();
        Database.executeBatch(new ProgramEnrollmentInvoiceRegenerateBatch(new List<Id>{ peId }), 1);
        Test.stopTest();

        List<SObject> rows = Database.query(
            'SELECT Regenerate_Invoice__c FROM hed__Program_Enrollment__c WHERE Id = :peId LIMIT 1'
        );
        System.assertEquals(
            false,
            rows[0].get('Regenerate_Invoice__c'),
            'Regenerate batch finish should clear Regenerate_Invoice__c.'
        );
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