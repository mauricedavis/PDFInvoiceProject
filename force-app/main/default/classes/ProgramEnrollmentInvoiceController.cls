public without sharing class ProgramEnrollmentInvoiceController {
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
        if (peId != null) { load(peId); computeTotals(); }
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

        hed__Program_Enrollment__c pe = [
            SELECT Id, Name, hed__Contact__r.Name
            FROM hed__Program_Enrollment__c WHERE Id = :programEnrollmentId
        ];

        String student = (pe.hed__Contact__r != null ? pe.hed__Contact__r.Name : 'Student').replaceAll('[^A-Za-z0-9]+','_');
        String peName  = (pe.Name != null ? pe.Name : 'ProgramEnrollment').replaceAll('[^A-Za-z0-9]+','_');
        String dateStr = Datetime.now().format('yyyy_MM_dd');
        String title   = 'Invoice_' + student + '_' + peName + '_' + dateStr;
        if (title.length() > 240) title = title.substring(0,240);

        ContentVersion cv = new ContentVersion(
            Title        = title,
            PathOnClient = title + '.pdf',
            VersionData  = pdf,
            Origin       = 'H'
        );
        insert cv;

        Id cdId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(ContentDocumentId = cdId, LinkedEntityId = programEnrollmentId, ShareType = 'V');

        update new hed__Program_Enrollment__c(
            Id = programEnrollmentId,
            Invoice_Created__c = true,
            Last_Invoice_ContentVersion_Id__c = cv.Id
        );
        return cv.Id;
    }

    @AuraEnabled
    public static Id generateAttachAndEmail(Id programEnrollmentId, List<String> additionalToAddresses) {
        Id cvId = generateAndAttach(programEnrollmentId);

        hed__Program_Enrollment__c pe = [
            SELECT Id, Name, hed__Account__r.Name,
                   hed__Contact__c, hed__Contact__r.Name, hed__Contact__r.Email
            FROM hed__Program_Enrollment__c WHERE Id = :programEnrollmentId
        ];
        ContentVersion cv = [SELECT Id, Title, VersionData, FileExtension, ContentDocumentId FROM ContentVersion WHERE Id = :cvId];

        String toAddr  = (pe.hed__Contact__r != null) ? pe.hed__Contact__r.Email : null;
        String subject = 'Invoice – ' + pe.Name + ' (' + pe.hed__Account__r.Name + ')';
        String body    = 'Hello ' + (pe.hed__Contact__r != null ? pe.hed__Contact__r.Name : 'Student') +
                         ',\n\nAttached is your invoice for the program enrollment. Thank you.\n\nStudent Services';

        Messaging.EmailFileAttachment att = new Messaging.EmailFileAttachment();
        att.setFileName(cv.Title + '.' + cv.FileExtension);
        att.setInline(false);
        att.setBody(cv.VersionData);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        if (pe.hed__Contact__c != null) mail.setTargetObjectId(pe.hed__Contact__c);
        else if (toAddr != null)        mail.setToAddresses(new List<String>{ toAddr });
        mail.setWhatId(programEnrollmentId);
        mail.setSaveAsActivity(true);
        if (additionalToAddresses != null && !additionalToAddresses.isEmpty()) mail.setCcAddresses(additionalToAddresses);
        mail.setSubject(subject);
        mail.setPlainTextBody(body);
        mail.setFileAttachments(new Messaging.EmailFileAttachment[] { att });
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

        try {
            EmailMessage em = new EmailMessage(
                Subject=subject, FromAddress=UserInfo.getUserEmail(), ToAddress=toAddr,
                RelatedToId=programEnrollmentId, MessageDate=System.now(),
                Status='3', Incoming=false, TextBody=body
            );
            insert em;
            if (pe.hed__Contact__c != null) {
                insert new EmailMessageRelation(EmailMessageId=em.Id, RelationId=pe.hed__Contact__c, RelationType='ToAddress');
            }
            insert new ContentDocumentLink(ContentDocumentId=cv.ContentDocumentId, LinkedEntityId=em.Id, ShareType='V');
        } catch (Exception ignore) {
            System.debug('EMAIL_MESSAGE_CREATE_SKIPPED: ' + ignore.getMessage());
        }

        update new hed__Program_Enrollment__c(
            Id = programEnrollmentId,
            Invoice_Emailed__c = true,
            Invoice_Last_Sent__c = System.now(),
            Last_Invoice_ContentVersion_Id__c = cv.Id
        );
        return cv.Id;
    }
}