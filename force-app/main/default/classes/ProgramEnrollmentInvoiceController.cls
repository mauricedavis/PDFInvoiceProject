public with sharing class ProgramEnrollmentInvoiceController {

    @AuraEnabled
    public static Id generateAttachAndEmail(Id programEnrollmentId, List<String> emailAddresses) {
        hed__Program_Enrollment__c pe = [
            SELECT Id, Name,
                   hed__Contact__r.Name,
                   hed__Contact__r.Email
            FROM hed__Program_Enrollment__c
            WHERE Id = :programEnrollmentId
            LIMIT 1
        ];

        // Create a "friendly" title for the invoice PDF
        String today = Date.today().format('yyyy-MM-dd');
        String fileTitle = 'Invoice - ' + pe.hed__Contact__r.Name + ' - ' + pe.Name + ' - ' + today;

        // Generate the PDF
        PageReference pdfPage = Page.ProgramEnrollmentInvoicePDF;
        pdfPage.getParameters().put('id', pe.Id);
        Blob pdfBlob = pdfPage.getContentAsPDF();

        ContentVersion cv = new ContentVersion(
            Title = fileTitle,
            PathOnClient = fileTitle + '.pdf',
            VersionData = pdfBlob
        );
        insert cv;

        // Link file to Program Enrollment
        Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            LinkedEntityId = pe.Id,
            ContentDocumentId = contentDocId,
            ShareType = 'V'
        );

        // Send email
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(emailAddresses);
        email.setSubject('Invoice for Program Enrollment ' + pe.Name);
        email.setHtmlBody('Please find attached your invoice.');
        email.setFileAttachments(new Messaging.EmailFileAttachment[] {
            new Messaging.EmailFileAttachment(
                Body = pdfBlob,
                FileName = fileTitle + '.pdf'
            )
        });
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });

        return cv.Id;
    }
}