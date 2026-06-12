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
        hed__Term__c term = new hed__Term__c(
            Name = 'Test Term 2026',
            hed__Account__c = acct.Id
        );
        insert term;
        Term_Enrollment__c te = new Term_Enrollment__c(
            Program_Enrollment__c = pe.Id,
            Term__c = term.Id
        );
        insert te;
        insert new hed__Course_Enrollment__c(
            Term_Enrollment__c = te.Id
        );
        update new hed__Program_Enrollment__c(
            Id = pe.Id,
            Deb_Confirmation_Term__c = 'Test Term 2026'
        );
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

        Integer linkedOnPe = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.Title = 'CopyTest_Course Registration_.pdf'
        ];
        System.assertEquals(1, linkedOnPe, 'Copy should link the Contact PDF to the PE with its original title.');
        Integer stableOnPe = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.Title = 'Course Registration Responses'
        ];
        System.assertEquals(0, stableOnPe, 'Copy must not create a renamed Course Registration Responses file.');
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
                      AND ContentDocument.Title = 'Invocable_Course Registration_.pdf'
                ] > 0,
            'Invocable should link responses onto PE with the original FA title.'
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

        System.assertNotEquals(null, newVerId, 'Should link ContentVersion on PE using re-queried VersionData.');
        Integer linkedOnPe = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.Title = 'FA_Source_For_Requery.pdf'
        ];
        System.assertEquals(1, linkedOnPe, 'FA source PDF should be linked to PE with its original title.');
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

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocument.Title = 'Course Registration Responses'
            ],
            'When FA PDF is already on PE, copy must not add a renamed duplicate.'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocument.Title = 'FormAssembly_On_PE_Only.pdf'
            ],
            'Existing FA PDF on PE should remain.'
        );
    }

    @IsTest
    static void test_CopyResponsesPdfFromClassicAttachment() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new Attachment(
            ParentId = pe.hed__Contact__c,
            Name = 'Legacy_Course Registration_Attachment.pdf',
            Body = Blob.valueOf('classic attachment body'),
            ContentType = 'application/pdf'
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(pe.Id);
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocument.Title = 'Legacy_Course Registration_Attachment'
            ],
            'Classic Attachment fallback should publish to PE with the original filename.'
        );
    }

    @IsTest
    static void test_CopyResponsesPdf_idempotentWhenContactPdfAlreadyLinked() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion cv = new ContentVersion(
            Title         = 'Idempotent_Course Registration_.pdf',
            PathOnClient  = 'idem.pdf',
            VersionData   = Blob.valueOf('idem-body'),
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
        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(pe.Id);
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocumentId = :docId
            ],
            'Second copy call should not create duplicate links to the same ContentDocument.'
        );
    }

    @IsTest
    static void test_CopyResponsesPdf_keepsStableCopyWhenItIsTheOnlyResponsesPdf() {
        Account acct = new Account(Name = 'CopyResponses Stable Only');
        insert acct;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        ContentVersion stableOnly = new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Course_Registration_Responses.pdf',
            VersionData = Blob.valueOf('only responses pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert stableOnly;

        Test.startTest();
        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(pe.Id);
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocument.Title = 'Course Registration Responses'
            ],
            'Stable copy should remain when it is the only responses PDF on the PE.'
        );
    }

    @IsTest
    static void test_CopyResponsesPdf_removesLegacyStableDuplicateWhenFaPdfOnPe() {
        Account acct = new Account(Name = 'CopyResponses Dedupe Stable');
        insert acct;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        ContentVersion faOnPe = new ContentVersion(
            Title = 'Testy Tester_Course Registration_06/11/2026.pdf',
            PathOnClient = 'fa.pdf',
            VersionData = Blob.valueOf('fa responses'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert faOnPe;
        ContentVersion stableDuplicate = new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Course_Registration_Responses.pdf',
            VersionData = Blob.valueOf('stable duplicate'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert stableDuplicate;

        Test.startTest();
        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(pe.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocument.Title = 'Course Registration Responses'
            ],
            'Legacy stable duplicate should be removed when descriptive FA PDF exists on PE.'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :pe.Id
                  AND ContentDocument.Title = 'Testy Tester_Course Registration_06/11/2026.pdf'
            ],
            'Descriptive FA PDF should remain on PE.'
        );
    }

    @IsTest
    static void queueableSkipsProgramEnrollmentConfirmationWhenCurrentlyEnrolled() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion rv = new ContentVersion(
            Title          = 'Responses_CE',
            PathOnClient   = 'R.pdf',
            VersionData    = Blob.valueOf('r'),
            IsMajorVersion = true
        );
        insert rv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :rv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = pe.hed__Contact__c,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        ContentVersion iv = new ContentVersion(
            Title                  = 'Invoice_CE',
            PathOnClient           = 'I.pdf',
            VersionData            = Blob.valueOf('i'),
            IsMajorVersion         = true,
            FirstPublishLocationId = pe.Id
        );
        insert iv;

        pe.hed__Enrollment_Status__c = 'Currently Enrolled';
        update pe;

        Integer beforeCnt = countStudentConfirmationActivity(pe.Id);
        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }));
        Test.stopTest();

        System.assertEquals(
            beforeCnt,
            countStudentConfirmationActivity(pe.Id),
            'Queueable must not send registration+invoice email when PE is Already Currently Enrolled (payment path).'
        );
    }

    @IsTest
    static void test_ConfirmationTermFromTermEnrollment() {
        Account program = new Account(Name = 'Implementation Science Confirmation Term Test');
        insert program;
        Contact c = new Contact(
            FirstName = 'Term',
            LastName = 'ConfirmTest',
            Email = 'term.confirm.test@example.invalid'
        );
        insert c;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = program.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        System.assertEquals(
            false,
            ProgramEnrollmentStudentEmail.isConfirmationTermReady(pe.Id),
            'Without TE, template send should wait.'
        );

        hed__Term__c term = new hed__Term__c(
            Name = 'Spring 2026',
            hed__Account__c = program.Id
        );
        insert term;
        insert new Term_Enrollment__c(Program_Enrollment__c = pe.Id, Term__c = term.Id);

        System.assertEquals(
            true,
            ProgramEnrollmentStudentEmail.isConfirmationTermReady(pe.Id),
            'With TE term, confirmation should be ready.'
        );

        ProgramEnrollmentStudentEmail.ensureDebConfirmationTermStamped(pe.Id);
        pe = [
            SELECT Deb_Confirmation_Term__c
            FROM hed__Program_Enrollment__c
            WHERE Id = :pe.Id
        ];
        System.assertEquals('Spring 2026', pe.Deb_Confirmation_Term__c);
    }

    @IsTest
    static void test_EarlyReturnHelpersAndInvocable() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, Deb_Confirmation_Term__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        ProgramEnrollmentStudentEmail.copyResponsesPdfToProgramEnrollment(null);
        ProgramEnrollmentStudentEmail.sendStudentEmail(null);
        ProgramEnrollmentStudentEmail.sendStudentEmail(
            new List<ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest>()
        );
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>());
        ProgramEnrollmentStudentEmail.ensureDebConfirmationTermStamped(null);

        System.assertEquals(null, ProgramEnrollmentStudentEmail.getContactId(null));
        System.assertNotEquals(null, ProgramEnrollmentStudentEmail.getContactId(pe.Id));

        ProgramEnrollmentStudentEmail.ensureDebConfirmationTermStamped(pe.Id);
        System.assertEquals(
            'Test Term 2026',
            [SELECT Deb_Confirmation_Term__c FROM hed__Program_Enrollment__c WHERE Id = :pe.Id].Deb_Confirmation_Term__c,
            'Pre-stamped term should not be overwritten.'
        );

        ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest req =
            new ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;
        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmail(
            new List<ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();
    }

    @IsTest
    static void test_ConfirmationEmailRequiresTwoFileAttachments() {
        hed__Program_Enrollment__c pe = [
            SELECT Id,
                   hed__Contact__c,
                   hed__Contact__r.Name,
                   hed__Contact__r.Email,
                   hed__Account__c,
                   hed__Account__r.Name
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Course_Registration_Responses.pdf',
            VersionData = Blob.valueOf('responses-pdf-bytes'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert new ContentVersion(
            Title = 'Invoice_AttachTest',
            PathOnClient = 'Invoice_AttachTest.pdf',
            VersionData = Blob.valueOf('invoice-pdf-bytes'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Send should succeed when both PDF VersionData blobs load as file attachments.'
        );
    }

    @IsTest
    static void test_QueueableForceResendConstructor() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Course_Registration_Responses.pdf',
            VersionData = Blob.valueOf('queueable-force-resp'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert new ContentVersion(
            Title = 'Invoice_QueueableForce',
            PathOnClient = 'Invoice_QueueableForce.pdf',
            VersionData = Blob.valueOf('queueable-force-inv'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }, true));
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Queueable forceResend constructor should send confirmation with attachments.'
        );
    }

    @IsTest
    static void test_ForceResendBypassesInternalSendDedupe() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new Task(
            WhatId = pe.Id,
            WhoId = pe.hed__Contact__c,
            Subject = 'Program Enrollment Confirmation - Internal Dedupe Test',
            ActivityDate = Date.today()
        );
        insert new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Course_Registration_Responses.pdf',
            VersionData = Blob.valueOf('internal-dedupe-resp'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert new ContentVersion(
            Title = 'Invoice_InternalDedupe',
            PathOnClient = 'Invoice_InternalDedupe.pdf',
            VersionData = Blob.valueOf('internal-dedupe-inv'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id }, true);
        Test.stopTest();

        System.assert(
            [
                    SELECT COUNT()
                    FROM Task
                    WHERE WhatId = :pe.Id AND Subject LIKE 'Program Enrollment Confirmation%'
                ] > 1,
            'forceResend should bypass internal 24h dedupe.'
        );
    }

    @IsTest
    static void test_SkipsSendWhenAttachmentIdsMissing() {
        Account isProgram = new Account(Name = 'Attachment Id Skip Program');
        insert isProgram;
        Contact c = new Contact(
            FirstName = 'Skip',
            LastName = 'Ids',
            Email = 'skip.ids@example.invalid'
        );
        insert c;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = isProgram.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Task
                WHERE WhatId = :pe.Id AND Subject LIKE 'Program Enrollment Confirmation%'
            ],
            'Send must not proceed without both PDF ContentVersion Ids.'
        );
    }

    @IsTest
    static void test_WrongSubjectDoesNotBlockResend() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new Task(
            WhatId = pe.Id,
            WhoId = pe.hed__Contact__c,
            Subject = 'Enrollment Confirmation',
            ActivityDate = Date.today(),
            Description = 'Short wrong-template resend should not dedupe the correct confirmation.'
        );
        ContentVersion resp = new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'wrong-subj-r.pdf',
            VersionData = Blob.valueOf('r'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert resp;
        insert new ContentVersion(
            Title = 'Invoice_WrongSubj',
            PathOnClient = 'wrong-subj-i.pdf',
            VersionData = Blob.valueOf('i'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        Integer confirmationTasks = [
            SELECT COUNT()
            FROM Task
            WHERE WhatId = :pe.Id
              AND Subject LIKE 'Program Enrollment Confirmation%'
        ];
        System.assert(
            confirmationTasks > 0,
            'Wrong-subject task must not prevent Program Enrollment Confirmation send.'
        );
    }

    @IsTest
    static void test_IsConfirmationSendDoesNotRequireDebTerm() {
        Account isProgram = new Account(Name = 'Online Certificate in Implementation Science');
        insert isProgram;
        Contact c = new Contact(
            FirstName = 'NoTerm',
            LastName = 'Required',
            Email = 'noterm.required@example.invalid'
        );
        insert c;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = isProgram.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
        ContentVersion resp = new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'r.pdf',
            VersionData = Blob.valueOf('r'),
            IsMajorVersion = true
        );
        insert resp;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :resp.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = c.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert new ContentVersion(
            Title = 'Invoice_NoTermReq',
            PathOnClient = 'i.pdf',
            VersionData = Blob.valueOf('i'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'IS confirmation should send without Deb_Confirmation_Term__c or TE.'
        );
    }

    @IsTest
    static void test_AdHocConfirmationTermReady_legacyWrapper() {
        Account isProgram = new Account(Name = 'Implementation Science legacy wrapper');
        insert isProgram;
        Contact c = new Contact(FirstName = 'Legacy', LastName = 'Wrap', Email = 'legacy.wrap@example.invalid');
        insert c;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = isProgram.Id,
            hed__Contact__c = c.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        System.assertEquals(
            true,
            ProgramEnrollmentStudentEmail.isAdHocConfirmationTermReady(pe.Id, isProgram.Id, isProgram.Name),
            'Non–Ad Hoc legacy wrapper should not gate on TE.'
        );
        System.assertEquals(
            false,
            ProgramEnrollmentStudentEmail.hasTermEnrollmentWithTerm(null),
            'Null PE id should not have TE.'
        );

        Account adHoc = new Account(Name = 'Ad Hoc Clinical Research Course program');
        insert adHoc;
        pe.hed__Account__c = adHoc.Id;
        update pe;
        System.assertEquals(
            false,
            ProgramEnrollmentStudentEmail.isAdHocConfirmationTermReady(pe.Id, adHoc.Id, adHoc.Name),
            'Ad Hoc without TE should not be ready via legacy wrapper.'
        );
    }

    @IsTest
    static void test_StudentConfirmationAttachmentsReady_falseWithoutInvoice() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'responses.pdf',
            VersionData = Blob.valueOf('responses-only'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        ProgramEnrollmentInvoiceController.deleteGeneratedInvoiceContentDocuments(pe.Id);

        System.assertEquals(
            false,
            ProgramEnrollmentStudentEmail.isStudentConfirmationAttachmentsReady(pe.Id),
            'Responses without invoice should not be ready.'
        );
        System.assertEquals(
            false,
            ProgramEnrollmentStudentEmail.isInvoiceAttachmentReady(pe.Id),
            'Invoice helper should be false when no invoice exists.'
        );
    }

    @IsTest
    static void test_StudentConfirmationAttachmentsReady_trueWithBothPdfs() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'responses.pdf',
            VersionData = Blob.valueOf('responses-ready'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert new ContentVersion(
            Title = 'Invoice_ReadinessTest',
            PathOnClient = 'invoice.pdf',
            VersionData = Blob.valueOf('invoice-ready'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        System.assertEquals(
            true,
            ProgramEnrollmentStudentEmail.isStudentConfirmationAttachmentsReady(pe.Id),
            'Both PDFs with settled course rows should be ready.'
        );
        System.assertEquals(
            true,
            ProgramEnrollmentStudentEmail.isInvoiceAttachmentReady(pe.Id),
            'Invoice helper should be true when invoice is attachable.'
        );
    }

    @IsTest
    static void test_ConfirmationTaskAloneDoesNotBlockResend() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new Task(
            WhatId = pe.Id,
            WhoId = pe.hed__Contact__c,
            Subject = 'Program Enrollment Confirmation - Partial Send Task',
            ActivityDate = Date.today()
        );
        insert new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'responses.pdf',
            VersionData = Blob.valueOf('retry-resp'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert new ContentVersion(
            Title = 'Invoice_RetryTest',
            PathOnClient = 'invoice.pdf',
            VersionData = Blob.valueOf('retry-inv'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        System.assert(
            countStudentConfirmationActivity(pe.Id) > 0,
            'Prior confirmation Task alone should not block a complete resend when no complete EmailMessage exists.'
        );
    }

    @IsTest
    static void test_ParseStringToSalesforceId_edgeCases() {
        System.assertEquals(null, ProgramEnrollmentStudentEmail.testParseStringToSalesforceId(null));
        System.assertEquals(null, ProgramEnrollmentStudentEmail.testParseStringToSalesforceId('not-an-id'));
        System.assertNotEquals(
            null,
            ProgramEnrollmentStudentEmail.testParseStringToSalesforceId(UserInfo.getUserId())
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
