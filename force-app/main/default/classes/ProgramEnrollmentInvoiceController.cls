public with sharing class ProgramEnrollmentInvoiceController {
    @AuraEnabled
    public static Id generateAttachAndEmail(Id peId, List<String> recipients) {
        hed__Program_Enrollment__c pe = [
            SELECT Id, Name, hed__Contact__r.Name, CreatedDate
            FROM hed__Program_Enrollment__c
            WHERE Id = :peId
            LIMIT 1
        ];

        String studentName   = pe.hed__Contact__r.Name;
        String peName        = pe.Name;
        String formattedDate = String.valueOf(System.today());

        // Human-friendly PDF title: StudentName_PEName_Date
        String fileName = studentName.replace(' ', '_') + '_' + peName + '_' + formattedDate + '.pdf';

        // TODO: Add logic for PDF generation + ContentVersion insert + Email send
        return null;
    }
}