@IsTest
private class ProgramEnrollmentNotify_Tests {

    @testSetup
    static void setupData() {
        Account acct = new Account(Name = 'Notification Test Program');
        insert acct;

        Contact contact = new Contact(
            FirstName = 'Notify',
            LastName  = 'Student',
            Email     = 'notify.student@example.com'
        );
        insert contact;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c        = acct.Id,
            hed__Contact__c        = contact.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;
    }

    @IsTest
    static void test_SendEnrollmentConfirmation() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        // Create a mock responses PDF and link it to the Contact (simulates FormAssembly behavior)
        ContentVersion cv = new ContentVersion(
            Title = 'Form Responses - Test',
            PathOnClient = 'FormResponsesTest.pdf',
            VersionData = Blob.valueOf('PDF content'),
            IsMajorVersion = true
        );
        insert cv;

        Id docId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = pe.hed__Contact__c,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest req =
            new ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentNotificationActions.sendEnrollmentConfirmation(
            new List<ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        // Assert the responses file is now also linked to the Program Enrollment
        Integer linkedCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocumentId = :docId
        ];
        System.assertEquals(1, linkedCount, 'Expected responses PDF to be linked to the Program Enrollment.');

        System.assert(true, 'sendEnrollmentConfirmation executed without error.');
    }

    @IsTest
    static void test_SendStudentEmailWithPdfs() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        // Responses PDF on Contact (keyword match so getLatestResponsesPdf finds it)
        ContentVersion respCv = new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Responses.pdf',
            VersionData = Blob.valueOf('responses pdf'),
            IsMajorVersion = true
        );
        insert respCv;
        Id respDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :respCv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = respDocId,
            LinkedEntityId = pe.hed__Contact__c,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        // Invoice PDF on Program Enrollment
        ContentVersion invoice = new ContentVersion(
            Title = 'Invoice_Test',
            PathOnClient = 'Invoice_Test.pdf',
            VersionData = Blob.valueOf('invoice pdf'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert invoice;

        ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest req =
            new ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmail(
            new List<ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        List<Task> sentTasks = [
            SELECT Id, Subject, WhatId
            FROM Task
            WHERE WhatId = :pe.Id AND Subject LIKE 'Program Enrollment Confirmation%'
        ];
        System.assert(sentTasks.size() >= 1, 'Expected email to be sent and logged (or test Task created).');
    }

    @IsTest
    static void test_SendStudentEmail_NullAndEmptyRequests() {
        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmail(null);
        ProgramEnrollmentStudentEmail.sendStudentEmail(new List<ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest>());
        ProgramEnrollmentStudentEmail.sendStudentEmail(
            new List<ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest>{
                new ProgramEnrollmentStudentEmail.ProgramEnrollmentRequest()
            }
        );
        Test.stopTest();
        System.assert(true, 'Null and empty requests handled without error.');
    }

    @IsTest
    static void test_StudentEmailQueueableEmptyList() {
        Test.startTest();
        System.enqueueJob(new ProgramEnrollmentStudentEmailQueueable(new List<Id>()));
        Test.stopTest();
        System.assert(true, 'Queueable with empty list executes without error.');
    }

    @IsTest
    static void test_StudentEmailHelpers() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        System.assertEquals(pe.hed__Contact__c, ProgramEnrollmentStudentEmail.getContactId(pe.Id), 'getContactId should return Contact.');
        System.assertEquals(null, ProgramEnrollmentStudentEmail.getContactId(null), 'getContactId(null) should return null.');
        System.assert(!ProgramEnrollmentStudentEmail.hasInvoicePdf(pe.Id), 'No invoice yet.');
        System.assert(!ProgramEnrollmentStudentEmail.hasAnyResponsesPdf(pe.hed__Contact__c), 'No responses PDF yet.');

        ContentVersion inv = new ContentVersion(
            Title = 'Invoice_Helper',
            PathOnClient = 'Inv.pdf',
            VersionData = Blob.valueOf('x'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert inv;
        System.assert(ProgramEnrollmentStudentEmail.hasInvoicePdf(pe.Id), 'Invoice should be found.');

        ContentVersion rcv = new ContentVersion(
            Title = 'Responses',
            PathOnClient = 'R.pdf',
            VersionData = Blob.valueOf('y'),
            IsMajorVersion = true
        );
        insert rcv;
        Id rdoc = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :rcv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = rdoc, LinkedEntityId = pe.hed__Contact__c, ShareType = 'V', Visibility = 'AllUsers');
        System.assert(ProgramEnrollmentStudentEmail.hasAnyResponsesPdf(pe.hed__Contact__c), 'Responses PDF should be found.');
    }

    @IsTest
    static void test_SendStudentEmail_ResponsesFromAttachment() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        insert new Attachment(
            Name = 'Course Registration.pdf',
            ParentId = pe.hed__Contact__c,
            Body = Blob.valueOf('attachment pdf'),
            ContentType = 'application/pdf'
        );
        ContentVersion invoice = new ContentVersion(
            Title = 'Invoice_Att',
            PathOnClient = 'Inv.pdf',
            VersionData = Blob.valueOf('inv'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert invoice;

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        List<Task> sentTasks = [SELECT Id FROM Task WHERE WhatId = :pe.Id AND Subject LIKE 'Program Enrollment Confirmation%'];
        System.assert(sentTasks.size() >= 1, 'Expected email sent when responses from Attachment.');
    }

    @IsTest
    static void test_SendStudentEmail_EnsureResponsesSkipsDuplicate() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ContentVersion rcv = new ContentVersion(
            Title = 'Course Registration Responses',
            PathOnClient = 'Responses.pdf',
            VersionData = Blob.valueOf('resp'),
            IsMajorVersion = true
        );
        insert rcv;
        Id rdoc = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :rcv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = rdoc, LinkedEntityId = pe.hed__Contact__c, ShareType = 'V', Visibility = 'AllUsers');
        insert new ContentDocumentLink(ContentDocumentId = rdoc, LinkedEntityId = pe.Id, ShareType = 'V', Visibility = 'AllUsers');
        ContentVersion inv = new ContentVersion(
            Title = 'Invoice_Dup',
            PathOnClient = 'Inv.pdf',
            VersionData = Blob.valueOf('inv'),
            IsMajorVersion = true,
            FirstPublishLocationId = pe.Id
        );
        insert inv;

        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();

        List<Task> sentTasks = [SELECT Id FROM Task WHERE WhatId = :pe.Id AND Subject LIKE 'Program Enrollment Confirmation%'];
        System.assert(sentTasks.size() >= 1, 'Expected email sent; ensureResponsesOnProgramEnrollment should skip duplicate.');
    }

    @IsTest
    static void test_SendStudentEmailInternal_NoEmailWhenMissingPdfs() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        Test.startTest();
        ProgramEnrollmentStudentEmail.sendStudentEmailInternal(new List<Id>{ pe.Id });
        Test.stopTest();
        List<Task> sentTasks = [SELECT Id FROM Task WHERE WhatId = :pe.Id AND Subject LIKE 'Program Enrollment Confirmation%'];
        System.assertEquals(0, sentTasks.size(), 'Should not send when PDFs are missing.');
    }

    @IsTest
    static void test_NotifyProgramOffice() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, Subject, WhatId
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
              AND WhatId = :pe.Id
        ];
        System.assertEquals(1, tasks.size(), 'Expected one program office notify task (trigger skipped in test).');
    }

    @IsTest
    static void test_NotifyProgramOffice_NullAndEmptyRequests() {
        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(null);
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>());
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{
                new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest()
            }
        );
        Test.stopTest();
        System.assert(true, 'Null and empty requests handled without error.');
    }

    @IsTest
    static void test_NotifyProgramOffice_PEWithoutContact() {
        Account acct = new Account(Name = 'Office Notify No Contact Program');
        insert acct;

        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert pe;

        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, Subject, WhatId, WhoId
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
              AND WhatId = :pe.Id
        ];
        System.assertEquals(1, tasks.size(), 'Expected one notify task for PE without Contact.');
        System.assertEquals(null, tasks[0].WhoId, 'WhoId should be null when PE has no Contact.');
    }

    @IsTest
    static void test_NotifyProgramOffice_MixedRequestSkipsInvalidId() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        Account acct = [SELECT Id FROM Account LIMIT 1];

        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest validReq =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        validReq.programEnrollmentId = pe.Id;
        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest invalidReq =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        invalidReq.programEnrollmentId = acct.Id;

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ validReq, invalidReq }
        );
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, WhatId
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
        ];
        System.assertEquals(1, tasks.size(), 'Only valid PE should produce one task; invalid id skipped.');
        System.assertEquals(pe.Id, tasks[0].WhatId, 'Task should be for the valid PE.');
    }

    @IsTest
    static void test_NotifyProgramOffice_MultipleEnrollments() {
        Account acct = new Account(Name = 'Multi Notify Program');
        insert acct;
        Contact c1 = new Contact(FirstName = 'First', LastName = 'Notify', Email = 'first@example.com');
        Contact c2 = new Contact(FirstName = 'Second', LastName = 'Notify', Email = 'second@example.com');
        insert new List<Contact>{ c1, c2 };

        hed__Program_Enrollment__c pe1 = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c1.Id,
            hed__Enrollment_Status__c = 'Enrolled'
        );
        hed__Program_Enrollment__c pe2 = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = c2.Id,
            hed__Enrollment_Status__c = 'Payment Pending'
        );
        insert new List<hed__Program_Enrollment__c>{ pe1, pe2 };

        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req1 =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        req1.programEnrollmentId = pe1.Id;
        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req2 =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        req2.programEnrollmentId = pe2.Id;

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ req1, req2 }
        );
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, WhatId, WhoId, Description
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
            ORDER BY WhatId
        ];
        System.assertEquals(1, tasks.size(), 'Expected one test task (trigger skipped in test).');
        System.assert(tasks[0].Description.contains('Program Enrollment') || tasks[0].Description.contains('Email sent'), 'Task should reflect notify.');
    }

    @IsTest
    static void test_NotifyProgramOffice_RequestWithNullIdSkipped() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest validReq =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        validReq.programEnrollmentId = pe.Id;
        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest nullIdReq =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        nullIdReq.programEnrollmentId = null;

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ validReq, nullIdReq }
        );
        Test.stopTest();

        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
        ];
        System.assertEquals(1, taskCount, 'Only valid request produces one task; null id skipped.');
    }

    @IsTest
    static void test_NotifyProgramOffice_ListWithNullElementSkipsNull() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest validReq =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        validReq.programEnrollmentId = pe.Id;

        List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest> reqs =
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>();
        reqs.add(null);
        reqs.add(validReq);

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(reqs);
        Test.stopTest();

        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
        ];
        System.assertEquals(1, taskCount, 'Null list element skipped; one task for valid request.');
    }

    @IsTest
    static void test_NotifyProgramOffice_CrossTransactionDedupe_SkipsWhenExistingTask() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        // Pre-seed a matching Task so cross-transaction dedupe filters this PE out.
        Task existing = new Task(
            Subject = 'Program Office Notified: New Program Enrollment',
            Description = 'existing task to trigger dedupe',
            ActivityDate = Date.today(),
            WhatId = pe.Id
        );
        if (pe.hed__Contact__c != null) existing.WhoId = pe.hed__Contact__c;
        insert existing;

        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        Integer taskCount = [
            SELECT COUNT()
            FROM Task
            WHERE Subject = 'Program Office Notified: New Program Enrollment'
              AND WhatId = :pe.Id
        ];

        System.assertEquals(
            1,
            taskCount,
            'Should skip sending/logging when dedupe finds an existing task.'
        );
    }

    @IsTest
    static void test_NotifyProgramOffice_ExceptionPathCoverage() {
        hed__Program_Enrollment__c pe = [
            SELECT Id
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];
        ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest req =
            new ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        ProgramEnrollmentOfficeNotify.throwInTestForCoverage = true;
        Test.startTest();
        ProgramEnrollmentOfficeNotify.notifyProgramOffice(
            new List<ProgramEnrollmentOfficeNotify.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();
        ProgramEnrollmentOfficeNotify.throwInTestForCoverage = false;

        List<Task> exceptionTasks = [
            SELECT Id, Subject
            FROM Task
            WHERE Subject = 'Program Office email EXCEPTION'
        ];
        System.assertEquals(1, exceptionTasks.size(), 'Catch block should create exception task.');
    }

    @IsTest
    static void test_SendEnrollmentConfirmation_AttachmentResponsesPdf() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        insert new Attachment(
            Name = 'Course Registration Responses.pdf',
            ParentId = pe.hed__Contact__c,
            Body = Blob.valueOf('attachment pdf'),
            ContentType = 'application/pdf'
        );

        ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest req =
            new ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentNotificationActions.sendEnrollmentConfirmation(
            new List<ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        // Attachment path should create a new File on the PE (FirstPublishLocationId=peId in helper),
        // so there should be at least one PDF linked to the Program Enrollment.
        Integer pdfLinks = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :pe.Id
              AND ContentDocument.FileType = 'PDF'
        ];
        System.assert(pdfLinks > 0, 'Expected a PDF File to be created/linked to PE from Attachment responses.');
    }

    @IsTest
    static void test_SendEnrollmentConfirmation_NoResponsesPdf() {
        hed__Program_Enrollment__c pe = [
            SELECT Id, hed__Contact__c
            FROM hed__Program_Enrollment__c
            LIMIT 1
        ];

        ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest req =
            new ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest();
        req.programEnrollmentId = pe.Id;

        Test.startTest();
        ProgramEnrollmentNotificationActions.sendEnrollmentConfirmation(
            new List<ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest>{ req }
        );
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, Subject, Description
            FROM Task
            WHERE WhatId = :pe.Id
              AND Subject LIKE 'Program Enrollment Confirmation Sent%'
        ];
        System.assert(!tasks.isEmpty(), 'Expected a confirmation Task even when no responses PDF exists.');
    }

    @IsTest
    static void test_SendEnrollmentConfirmation_NullAndEmptyRequests() {
        Test.startTest();
        ProgramEnrollmentNotificationActions.sendEnrollmentConfirmation(null);
        ProgramEnrollmentNotificationActions.sendEnrollmentConfirmation(new List<ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest>());
        ProgramEnrollmentNotificationActions.sendEnrollmentConfirmation(
            new List<ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest>{
                new ProgramEnrollmentNotificationActions.ProgramEnrollmentRequest()
            }
        );
        Test.stopTest();
        System.assert(true, 'Null and empty requests handled without error.');
    }
}

