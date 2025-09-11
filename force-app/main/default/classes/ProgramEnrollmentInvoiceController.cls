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

        // Human-friendly file title
        String today = DateTime.now().format('yyyy-MM-dd');
        String fileTitle = 'Invoice - ' + pe.hed__Contact__r.Name + ' - ' + pe.Name + ' - ' + today;

        // Generate PDF
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

        // Send email with attachment
        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setBody(pdfBlob);
        attachment.setFileName(fileTitle + '.pdf');

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(emailAddresses);
        email.setSubject('Invoice for Program Enrollment ' + pe.Name);
        email.setHtmlBody('Please find attached your invoice.');
        email.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });

        return cv.Id;
    }
}