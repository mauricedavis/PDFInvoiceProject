List<hed__Program_Enrollment__c> pes = [
  SELECT Id, hed__Contact__c, hed__Contact__r.Email, Name
  FROM hed__Program_Enrollment__c
  WHERE hed__Contact__c != null
  ORDER BY LastModifiedDate DESC
  LIMIT 1
];
if (pes.isEmpty()) {
  System.debug('NO_PE_WITH_CONTACT');
} else {
  Id peId = pes[0].Id;
  System.debug('TESTING_PE=' + peId);
  Id cvId = ProgramEnrollmentInvoiceController.generateAttachAndEmail(peId, null);
  hed__Program_Enrollment__c pe = [
    SELECT Invoice_Created__c, Invoice_Emailed__c, Invoice_Last_Sent__c, Last_Invoice_ContentVersion_Id__c
    FROM hed__Program_Enrollment__c WHERE Id = :peId
  ];
  System.debug('CV_ID=' + cvId);
  System.debug('FLAGS=' + pe);
}