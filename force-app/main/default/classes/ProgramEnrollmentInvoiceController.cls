public with sharing class ProgramEnrollmentInvoiceController {
    public Id peId { get; private set; }
    public hed__Program_Enrollment__c progEnroll { get; private set; }
    public List<hed__Course_Enrollment__c> lines { get; private set; }
    public Decimal subtotal { get; private set; }
    public Decimal taxAmount { get; private set; }
    public Decimal total { get; private set; }

    public List<hed__Course_Enrollment__c> getLines() { return lines; }
    public hed__Program_Enrollment__c getProgEnroll() { return progEnroll; }

    public ProgramEnrollmentInvoiceController() {
        peId = ApexPages.currentPage().getParameters().get('id');
        load(peId);
        computeTotals();
    }

    private void load(Id programEnrollmentId) {
        progEnroll = [
            SELECT Id, Name,
                   hed__Contact__c, hed__Contact__r.Name, hed__Contact__r.Email,
                   hed__Account__r.Name, hed__Enrollment_Status__c,
                   Invoice_Created__c, Invoice_Emailed__c,
                   Invoice_Last_Sent__c, Last_Invoice_ContentVersion_Id__c
            FROM hed__Program_Enrollment__c
            WHERE Id = :programEnrollmentId
            LIMIT 1
        ];

        lines = [
            SELECT Id, Name, Role__c,
                   Term_Name__c, Course_Fee__c,
                   hed__Status__c,
                   hed__Course_Offering__r.hed__Start_Date__c,
                   hed__Course_Offering__r.hed__Course__r.Name
            FROM hed__Course_Enrollment__c
            WHERE hed__Program_Enrollment__c = :programEnrollmentId
            ORDER BY hed__Course_Offering__r.hed__Start_Date__c NULLS LAST, CreatedDate
        ];
    }

    private void computeTotals() {
        subtotal = 0;
        for (hed__Course_Enrollment__c ce : lines) {
            subtotal += (ce.Course_Fee__c == null ? 0 : ce.Course_Fee__c);
        }
        Decimal taxRate = 0;
        taxAmount = (subtotal * taxRate).setScale(2);
        total = (subtotal + taxAmount).setScale(2);
    }

    @AuraEnabled
    public static Id generateAndAttach(Id programEnrollmentId) {
        PageReference p = Page.ProgramEnrollmentInvoicePDF;
        p.getParameters().put('id', (String)programEnrollmentId);

        Blob pdf = Test.isRunningTest() ? Blob.valueOf('fake pdf') : p.getContentAsPDF();

        String title = 'Invoice_' + String.valueOf(programEnrollmentId).right(6);
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = pdf,
            Origin = 'H'
        );
        insert cv;

        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id]
                  .ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = cdId,
            LinkedEntityId = programEnrollmentId,
            ShareType = 'V'
        );

        // Mark created & remember last CV Id
        update new hed__Program_Enrollment__c(
            Id = programEnrollmentId,
            Invoice_Created__c = true,
            Last_Invoice_ContentVersion_Id__c = cv.Id
        );

        return cv.Id;
    }

    @AuraEnabled
    public static Id generateAttachAndEmail(Id programEnrollmentId, List<String> additionalToAddresses) {
        // 1) Always attach first (also sets Invoice_Created__c + last CV Id)
        Id cvId = generateAndAttach(programEnrollmentId);

        // 2) Gather email details
        hed__Program_Enrollment__c pe = [
            SELECT Id, Name, hed__Account__r.Name,
                   hed__Contact__c, hed__Contact__r.Name, hed__Contact__r.Email
            FROM hed__Program_Enrollment__c WHERE Id = :programEnrollmentId
        ];

        ContentVersion cv = [
            SELECT Id, Title, VersionData, FileExtension, ContentDocumentId
            FROM ContentVersion WHERE Id = :cvId
        ];

        String toAddr = (pe.hed__Contact__r != null) ? pe.hed__Contact__r.Email : null;
        String subject = 'Invoice – ' + pe.Name + ' (' + pe.hed__Account__r.Name + ')';
        String body = 'Hello ' +
            (pe.hed__Contact__r != null ? pe.hed__Contact__r.Name : 'Student') + ',\n\n' +
            'Attached is your invoice for the program enrollment. Thank you.\n\n' +
            'Student Services';

        // 3) Send the email
        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(cv.Title + '.' + cv.FileExtension);
        att.setInline(false);
        att.setBody(cv.VersionData);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        if (pe.hed__Contact__c != null) {
            mail.setTargetObjectId(pe.hed__Contact__c); // ensures activity against Contact
        } else if (toAddr != null) {
            mail.setToAddresses(new List<String>{ toAddr });
        }
        mail.setWhatId(programEnrollmentId);          // activity on Program Enrollment
        mail.setSaveAsActivity(true);
        if (additionalToAddresses != null && !additionalToAddresses.isEmpty()) {
            mail.setCcAddresses(additionalToAddresses);
        }
        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { att });

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        // 4) HARD AUDIT: create a Completed Task so you always see it on both records
        Task t = new Task(
            Subject      = 'Invoice emailed',
            Status       = 'Completed',
            Priority     = 'Normal',
            ActivityDate = Date.today(),
            WhatId       = programEnrollmentId,           // shows on Program Enrollment
            WhoId        = pe.hed__Contact__c             // shows on Contact (if present)
        );
        insert t;

        // 5) Link the file to the Task too (optional but handy)
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = t.Id,
            ShareType         = 'V'
        );

        // 6) Mark emailed & last-sent timestamp & last CV Id
        update new hed__Program_Enrollment__c(
            Id = programEnrollmentId,
            Invoice_Emailed__c = true,
            Invoice_Last_Sent__c = System.now(),
            Last_Invoice_ContentVersion_Id__c = cv.Id
        );

        return cvId;
    }
}