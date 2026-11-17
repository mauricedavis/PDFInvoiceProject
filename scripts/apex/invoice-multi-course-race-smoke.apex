List<hed__Course_Enrollment__c> seed = [
    SELECT Term_Enrollment__r.Program_Enrollment__c
    FROM hed__Course_Enrollment__c
    WHERE Term_Enrollment__c != NULL
      AND Term_Enrollment__r.Program_Enrollment__c != NULL
    LIMIT 1
];
Id peId = seed[0].Term_Enrollment__r.Program_Enrollment__c;
Integer termEnrollmentCount = [SELECT COUNT() FROM Term_Enrollment__c WHERE Program_Enrollment__c = :peId];
Integer ccCount = ProgramEnrollmentInvoiceController.countCourseConnectionsForProgramEnrollment(peId);
Boolean ready = ProgramEnrollmentInvoiceController.isReadyForInvoiceGeneration(peId);
Boolean stale = ProgramEnrollmentInvoiceController.isProgramEnrollmentInvoiceStale(peId);
System.assert(termEnrollmentCount > 0, 'Smoke needs at least one Term Enrollment.');
System.assert(ccCount > 0, 'Smoke needs at least one Course Connection.');
System.assert(ready, 'Matched TE/CC pair should be invoice-ready.');
System.debug(LoggingLevel.ERROR, 'INVOICE_RACE_SMOKE OK pe=' + peId + ' TE=' + termEnrollmentCount + ' CC=' + ccCount + ' stale=' + stale);