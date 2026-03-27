@IsTest
private class ProgramEnrollmentStudentEmail_Tests {

    @testSetup
    static void setupData() {
        Account acct = new Account(Name = 'Student Email Test Program');
        insert acct;
        Contact contact = new Contact(
            FirstName = 'Student',
            LastName  = 'Email',
            Email     = 'student.email@example.com'
        );
        insert contact;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c           = acct.Id,
            hed__Contact__c           = contact.Id,
            hed__Enrollment_Status__c  = 'Payment Pending'
        );
        insert pe;
    }

    @IsTest
    static void test_CopyResponsesPdfToProgramEnrollment_fromContact() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion cv = new ContentVersion(
            Title         = 'CopyTest_Course Registration_.pdf',
            PathOnClient  = 'c.pdf',
            VersionData   = Blob.valueOf('copy-body'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId   = pe.hed__Contact__c,
            ShareType        = 'V',
            Visibility       = 'AllUsers'
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(pe.Id);
        Test.stopTest();

        Integer stableOnPe = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.Title = 'Course Registration Responses'
        ];
        System.assertEquals(1, stableOnPe, 'Copy should publish Course Registration Responses on the PE.');
    }

    @IsTest
    static void test_CopyResponsesInvocable_delegatesToStudentEmail() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion cv = new ContentVersion(
            Title         = 'Invocable_Course Registration_.pdf',
            PathOnClient  = 'i.pdf',
            VersionData   = Blob.valueOf('inv'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId   = pe.hed__Contact__c,
            ShareType        = 'V',
            Visibility       = 'AllUsers'
        );
        ProgramEnrollmentCopyResponsesInvocable.ProgramEnrollmentRequest req =
            new ProgramEnrollmentCopyResponsesInvocable.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentCopyResponsesInvocable.copyResponsesPdfToProgramEnrollment(
            new List<ProgramEnrollmentCopyResponsesInvocable.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        System.assert(
            [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :pe.Id
                      AND ContentDocument.Title = 'Course Registration Responses'
                ] > 0,
            'Invocable should copy responses onto PE.'
        );
    }

    @IsTest
    static void test_FullFlowWithBothPdfsViaQueueable() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion respCv = new ContentVersion(
            Title = 'Form Responses',
            PathOnClient = 'Responses.pdf',
            VersionData  = Blob.valueOf('responses'),
            IsMajorVersion = true
        );
        insert respCv;
        Id respDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :respCv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = respDocId,
            LinkedEntityId   = pe.hed__Contact__c,
            ShareType        = 'V',
            Visibility       = 'AllUsers'
        );
        ContentVersion invCv = new ContentVersion(
            Title                  = 'My Invoice',
            PathOnClient           = 'MyInvoice.pdf',
            VersionData            = Blob.valueOf('invoice'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert invCv;

        ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest req =
            new ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmail(
            new List<ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Email send should be reflected as EmailMessage (prod) or Task (test) on the Program Enrollment.'
        );
    }

    @IsTest
    static void test_ResponsesPdfFromAnyFileNoKeyword() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion cv = new ContentVersion(
            Title         = 'SomeOtherDoc',
            PathOnClient  = 'Other.pdf',
            VersionData   = Blob.valueOf('pdf'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId   = pe.hed__Contact__c,
            ShareType        = 'V',
            Visibility       = 'AllUsers'
        );
        ContentVersion inv = new ContentVersion(
            Title                  = 'Invoice_Any',
            PathOnClient           = 'Inv.pdf',
            VersionData            = Blob.valueOf('inv'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert inv;

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Should use any PDF File when no keyword match.'
        );
    }

    @IsTest
    static void test_ResponsesPdfOnlyOnProgramEnrollment_FormAssembly() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        // FormAssembly often publishes the registration PDF to the PE, not the Contact.
        ContentVersion faCv = new ContentVersion(
            Title                  = 'Student_TEST_Course Registration_.pdf',
            PathOnClient           = 'fa.pdf',
            VersionData            = Blob.valueOf('fa responses'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert faCv;
        ContentVersion invCv = new ContentVersion(
            Title                  = 'Invoice_PE-FA-PE-Only',
            PathOnClient           = 'inv.pdf',
            VersionData            = Blob.valueOf('invoice body'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert invCv;

        System.assert(
            !ProgramEnrollmentStudentEmail.hasAnyResponsesPdf(pe.hed__Contact__c),
            'Contact should have no PDFs in this scenario.'
        );
        System.assert(
            ProgramEnrollmentStudentEmail.hasNonInvoicePdfOnProgramEnrollment(pe.Id),
            'PE should have a non-invoice PDF (FA responses).'
        );
        System.assert(
            ProgramEnrollmentStudentEmail.hasResponsesSourceForStudentEmail(pe.Id, pe.hed__Contact__c),
            'Readiness should pass when responses exist only on the PE.'
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Should send student confirmation using PE-linked FA responses PDF.'
        );
        Integer stableCopies = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.Title = 'Course Registration Responses'
        ];
        System.assertEquals(
            0,
            stableCopies,
            'PE-native path must not insert stable Course Registration Responses copy.'
        );
    }

    @IsTest
    static void test_QueueableReadyWhenContactNull_pdfsOnPe_noReadinessTimeoutTask() {
        Account acct = new Account(Name = 'Student Email No-Contact Queueable');
        insert acct;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        ContentVersion faCv = new ContentVersion(
            Title = 'FA_Queueable_NoContact.pdf',
            PathOnClient = 'fa.pdf',
            VersionData = Blob.valueOf('fa'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert faCv;
        ContentVersion invCv = new ContentVersion(
            Title = 'Invoice_Queueable_NoContact',
            PathOnClient = 'inv.pdf',
            VersionData = Blob.valueOf('inv'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert invCv;

        ProgramEnrollmentStudentEmail.allowLogReadinessTimeoutTasksInTest = true;
        try {
            Test.startTest();
            new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }, 40).execute(null);
            Test.stopTest();
        } finally {
            ProgramEnrollmentStudentEmail.allowLogReadinessTimeoutTasksInTest = false;
        }

        Integer timeoutTasks = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :pe.Id
              AND Subject LIKE 'Student confirmation NOT sent:%'
        ];
        System.assertEquals(
            0,
            timeoutTasks,
            'Readiness must not require Contact when non-invoice PDF and invoice exist on PE.'
        );
        System.assertEquals(
            0,
            countStudentConfirmationActivity(pe.Id),
            'No student email without Contact and email on PE.'
        );
    }

    @IsTest
    static void test_ResponsesPdfFromAnyAttachmentNoKeyword() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new Attachment(
            Name        = 'Random.pdf',
            ParentId    = pe.hed__Contact__c,
            Body        = Blob.valueOf('att pdf'),
            ContentType = 'application/pdf'
        );
        ContentVersion inv = new ContentVersion(
            Title                  = 'Invoice_Att2',
            PathOnClient           = 'Inv.pdf',
            VersionData            = Blob.valueOf('inv'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert inv;

        // Sanity: readiness checks should be true before we try sending.
        System.assert(
            ProgramEnrollmentStudentEmail.hasAnyResponsesPdf(pe.hed__Contact__c),
            'Expected contact to be considered as having a PDF response.'
        );
        System.assert(
            ProgramEnrollmentStudentEmail.hasInvoicePdf(pe.Id),
            'Expected PE to be considered as having an invoice PDF.'
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        Integer emCnt = [
            SELECT COUNT()
            FROM EmailMessage
            WHERE RelatedToId = :pe.Id
              AND Subject LIKE 'Program Enrollment Confirmation%'
        ];
        Integer taskCnt = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :pe.Id
              AND Subject LIKE 'Program Enrollment Confirmation%'
              AND (NOT Subject LIKE '%dedupe token%')
        ];
        System.assert(
            (emCnt + taskCnt) > 0,
            'Expected activity for attachment fallback. EmailMessages=' + emCnt + ', Tasks=' + taskCnt
        );
    }

    @IsTest
    static void test_QueueableExecuteWithReadyData() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion rv = new ContentVersion(
            Title         = 'Responses',
            PathOnClient  = 'R.pdf',
            VersionData   = Blob.valueOf('r'),
            IsMajorVersion = true
        );
        insert rv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :rv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = pe.hed__Contact__c, ShareType = 'V', Visibility = 'AllUsers');
        ContentVersion iv = new ContentVersion(
            Title                  = 'Invoice_Q',
            PathOnClient           = 'I.pdf',
            VersionData            = Blob.valueOf('i'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert iv;

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }));
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Queueable execute should send and be logged.'
        );
    }

    @IsTest
    static void test_QueueableExecute_NotReadyPathReturns() {
        // Create a PE without any invoice/responses PDFs, so queueable is not ready.
        Account acct = new Account(Name = 'Student Email Not Ready Program');
        insert acct;
        Contact c = new Contact(FirstName = 'Not', LastName = 'Ready', Email = 'not.ready.student@example.com');
        insert c;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }));
        Test.stopTest();

        // Should return before sending internal email (no activity expected).
        System.assertEquals(0, countStudentConfirmationActivity(pe.Id), 'Not-ready path should not send.');
    }

    @IsTest
    static void test_QueueableExecute_MaxRetrySkipsReadinessCheck() {
        // Not ready and retry at/above max: no send (internal send is only when allReady).
        Account acct = new Account(Name = 'Student Email Max Retry Program');
        insert acct;
        Contact c = new Contact(FirstName = 'Max', LastName = 'Retry', Email = 'max.retry.student@example.com');
        insert c;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        Test.startTest();
        new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }, 40).execute(null);
        Test.stopTest();

        Integer sentCount = [
            SELECT COUNT()
            FROM EmailMessage
            WHERE RelatedToId = :pe.Id
              AND Subject LIKE 'Program Enrollment Confirmation%'
        ];
        System.assertEquals(0, sentCount, 'With no PDFs, internal send should skip.');
    }

    @IsTest
    static void test_SendStudentEmailInternal_EmptyList() {
        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>());
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(null);
        Test.stopTest();
        System.assert(true, 'Empty and null lists handled.');
    }

    @IsTest
    static void test_HasInvoicePdfAndHasAnyResponsesPdf_NullIds() {
        System.assert(!ProgramEnrollmentStudentEmail.hasInvoicePdf(null), 'hasInvoicePdf(null) should be false.');
        System.assert(!ProgramEnrollmentStudentEmail.hasAnyResponsesPdf(null), 'hasAnyResponsesPdf(null) should be false.');
        System.assert(!ProgramEnrollmentStudentEmail.hasNonInvoicePdfOnProgramEnrollment(null), 'PE null should be false.');
        System.assert(!ProgramEnrollmentStudentEmail.hasResponsesSourceForStudentEmail(null, null), 'Null PE should be false.');
    }

    @IsTest
    static void test_HasNonInvoicePdfOnPe_falseWhenOnlyInvoice() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion invOnly = new ContentVersion(
            Title                  = 'Invoice_Only_Test',
            PathOnClient           = 'inv.pdf',
            VersionData            = Blob.valueOf('x'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert invOnly;
        System.assert(
            !ProgramEnrollmentStudentEmail.hasNonInvoicePdfOnProgramEnrollment(pe.Id),
            'Invoice-only PE should not count as responses source.'
        );
        System.assert(
            !ProgramEnrollmentStudentEmail.hasResponsesSourceForStudentEmail(pe.Id, pe.hed__Contact__c),
            'No contact PDF and only invoice on PE: not ready.'
        );
    }

    @IsTest
    static void test_QueueableReadyWhenResponsesOnlyOnPe() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion faCv = new ContentVersion(
            Title                  = 'FA_On_PE_Only.pdf',
            PathOnClient           = 'fa.pdf',
            VersionData            = Blob.valueOf('fa'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert faCv;
        ContentVersion invCv = new ContentVersion(
            Title                  = 'Invoice_PE-QPE',
            PathOnClient           = 'i.pdf',
            VersionData            = Blob.valueOf('i'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert invCv;

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }));
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Queueable should treat PE-only FA PDF as responses and send.'
        );
    }

    @IsTest
    static void test_LogReadinessTimeoutTasks_insertsTaskWhenEnabled() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ProgramEnrollmentStudentEmail.allowLogReadinessTimeoutTasksInTest = true;
        try {
            ProgramEnrollmentStudentEmail.logReadinessTimeoutTasks(new List<Id>{ pe.Id });
        } finally {
            ProgramEnrollmentStudentEmail.allowLogReadinessTimeoutTasksInTest = false;
        }
        Integer taskCnt = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :pe.Id
              AND Subject LIKE 'Student confirmation NOT sent:%'
        ];
        System.assert(taskCnt > 0, 'Timeout log task should be inserted when test flag is on.');
    }

    @IsTest
    static void test_OrgWideEmailLookupPath_exercisedInTest() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion faCv = new ContentVersion(
            Title                  = 'OWEA_Coverage_FA.pdf',
            PathOnClient           = 'fa.pdf',
            VersionData            = Blob.valueOf('fa'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert faCv;
        ContentVersion invCv = new ContentVersion(
            Title                  = 'Invoice_OWEA-Cov',
            PathOnClient           = 'i.pdf',
            VersionData            = Blob.valueOf('i'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert invCv;

        ProgramEnrollmentStudentEmail.resetOweaCacheForTest();
        ProgramEnrollmentStudentEmail.allowOrgWideEmailLookupInTest = true;
        try {
            Test.startTest();
            ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
            Test.stopTest();
        } finally {
            ProgramEnrollmentStudentEmail.allowOrgWideEmailLookupInTest = false;
            ProgramEnrollmentStudentEmail.resetOweaCacheForTest();
        }
        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Send path with OWEA lookup enabled in test should still complete.'
        );
    }

    @IsTest
    static void test_EnsureResponses_requeriesVersionDataWhenBodyNull() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion src = new ContentVersion(
            Title = 'FA_Source_For_Requery.pdf',
            PathOnClient = 'src.pdf',
            VersionData = Blob.valueOf('synthetic pdf body for requery path'),
            IsMajorVersion = true
        );
        insert src;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :src.Id LIMIT 1].ContentDocumentId;

        Test.startTest();
        Id newVerId = ProgramEnrollmentStudentEmail.testEnsureResponsesFromContentDocumentIdOnly(pe.Id, docId);
        Test.stopTest();

        System.assertNotEquals(null, newVerId, 'Should insert stable ContentVersion on PE using re-queried VersionData.');
        Integer stableOnPe = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.Title = 'Course Registration Responses'
        ];
        System.assertEquals(1, stableOnPe, 'Stable Course Registration Responses file should be linked to PE.');
    }

    @IsTest
    static void test_CopyResponsesPdf_withoutContact_whenPdfOnlyOnPe() {
        Account acct = new Account(Name = 'CopyResponses No-Contact PE');
        insert acct;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        ContentVersion faOnPe = new ContentVersion(
            Title = 'FormAssembly_On_PE_Only.pdf',
            PathOnClient = 'fa.pdf',
            VersionData = Blob.valueOf('responses on pe'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert faOnPe;

        Test.startTest();
        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(pe.Id);
        Test.stopTest();

        System.assert(
            [
                    SELECT COUNT()
                    FROM ContentDocumentLink
                    WHERE LinkedEntityId = :pe.Id
                      AND ContentDocument.Title = 'Course Registration Responses'
                ] > 0,
            'copyResponsesPdfToProgramEnrollment should work when Contact is null but a non-invoice PDF is on the PE.'
        );
    }

    /** Production logs EmailMessage; unit tests log Task. Count either (exclude legacy dedupe-token tasks). */
    private static Integer countStudentConfirmationActivity(Id peId) {
        Integer emCnt = [
            SELECT COUNT()
            FROM EmailMessage
            WHERE RelatedToId = :peId
              AND Subject LIKE 'Program Enrollment Confirmation%'
        ];
        Integer taskCnt = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :peId
              AND Subject LIKE 'Program Enrollment Confirmation%'
              AND (NOT Subject LIKE '%dedupe token%')
        ];
        return emCnt + taskCnt;
    }
}
