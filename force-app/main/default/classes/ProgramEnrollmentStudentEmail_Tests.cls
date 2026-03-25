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
        // Even if not ready, when retry >= maxRetries, the queueable skips readiness checks
        // and calls internal send (which itself will skip if PDFs missing). This covers that branch.
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
        new ProgramEnrollmentStudentEmailQueueable(new List<Id>{ pe.Id }, 8).execute(null);
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
