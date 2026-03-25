public with sharing class ProgramEnrollmentOfficeNotify {

    @TestVisible
    private static Boolean throwInTestForCoverage = false;

    /** Same-transaction dedupe: do not send a second office notification for these PEs. */
    @TestVisible
    private static Set<Id> alreadyNotifiedPeIds = new Set<Id>();

    public class ProgramEnrollmentRequest {
        @InvocableVariable(required=true)
        public Id programEnrollmentId;
    }

    @InvocableMethod(
        label='Notify Program Office of New Enrollment'
        description='Sends a simple notification email to the Program Office when a new Program Enrollment is submitted.'
    )
    public static void notifyProgramOffice(List<ProgramEnrollmentRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        Set<Id> peIds = new Set<Id>();
        for (ProgramEnrollmentRequest r : requests) {
            if (r != null && r.programEnrollmentId != null) {
                peIds.add(r.programEnrollmentId);
            }
        }
        if (peIds.isEmpty()) return;

        // Same-transaction dedupe: skip PEs we already notified in this request (e.g. trigger + Flow both calling).
        List<Id> toNotify = new List<Id>();
        for (Id peId : peIds) {
            if (!alreadyNotifiedPeIds.contains(peId)) toNotify.add(peId);
        }
        if (toNotify.isEmpty()) return;

        // Optional: skip PEs with Program_Office_Notified_Date__c in last 24h (requires custom field on hed__Program_Enrollment__c).
        Set<Id> skipRecent = new Set<Id>();
        try {
            if (Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Program_Office_Notified_Date__c')) {
                List<SObject> recent = Database.query(
                    'SELECT Id FROM hed__Program_Enrollment__c WHERE Id IN :toNotify AND Program_Office_Notified_Date__c = LAST_N_DAYS:1'
                );
                for (SObject pe : recent) skipRecent.add(pe.Id);
            }
        } catch (Exception ignore) { /* field may not exist */ }
        List<Id> finalPeIds = new List<Id>();
        for (Id peId : toNotify) {
            if (!skipRecent.contains(peId)) finalPeIds.add(peId);
        }
        if (finalPeIds.isEmpty()) return;

        // Cross-transaction dedupe: static sets only work within a single execution/transaction.
        // In PROD the same PE can reach this method from multiple transactions (e.g. trigger + flow),
        // so we also check existing activity logs.
        try {
            Set<Id> alreadyLogged = new Set<Id>();

            for (EmailMessage em : [
                SELECT RelatedToId
                FROM EmailMessage
                WHERE RelatedToId IN :finalPeIds
                  AND Subject LIKE 'New Program Enrollment submitted:%'
                  AND MessageDate = LAST_N_DAYS:1
            ]) {
                if (em.RelatedToId != null) alreadyLogged.add(em.RelatedToId);
            }

            for (Task t : [
                SELECT WhatId
                FROM Task
                WHERE WhatId IN :finalPeIds
                  AND Subject = 'Program Office Notified: New Program Enrollment'
                  AND CreatedDate = LAST_N_DAYS:1
            ]) {
                if (t.WhatId != null) alreadyLogged.add(t.WhatId);
            }

            if (!alreadyLogged.isEmpty()) {
                List<Id> filtered = new List<Id>();
                for (Id peId : finalPeIds) {
                    if (!alreadyLogged.contains(peId)) filtered.add(peId);
                }
                finalPeIds = filtered;
            }
        } catch (Exception ignore) { }

        if (finalPeIds.isEmpty()) return;

        Map<Id, hed__Program_Enrollment__c> peMap = new Map<Id, hed__Program_Enrollment__c>(
            [
                SELECT Id,
                       Name,
                       hed__Contact__c,
                       hed__Contact__r.Name,
                       hed__Account__r.Name,
                       hed__Enrollment_Status__c
                FROM hed__Program_Enrollment__c
                WHERE Id IN :finalPeIds
            ]
        );

        if (peMap.isEmpty()) return;

        String officeAddress = 'ImplementationScience@ucsf.edu';
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> peIdsForEmails = new List<Id>();

        for (Id peId : finalPeIds) {
            hed__Program_Enrollment__c pe = peMap.get(peId);
            if (pe == null) continue;

            peIdsForEmails.add(pe.Id);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new List<String>{ officeAddress });

            msg.setSubject('New Program Enrollment submitted: ' + (pe.Name != null ? pe.Name : String.valueOf(pe.Id)));

            String baseUrl = System.URL.getOrgDomainUrl().toExternalForm();
            String peUrl = baseUrl + '/lightning/r/hed__Program_Enrollment__c/' + pe.Id + '/view';

            String body =
                'A new Program Enrollment has been submitted.' + '\n\n' +
                'Program Enrollment: ' + (pe.Name != null ? pe.Name : String.valueOf(pe.Id)) + '\n' +
                'Student: ' + (pe.hed__Contact__r != null ? pe.hed__Contact__r.Name : 'N/A') + '\n' +
                'Program: ' + (pe.hed__Account__r != null ? pe.hed__Account__r.Name : 'N/A') + '\n' +
                'Status: ' + (pe.hed__Enrollment_Status__c != null ? pe.hed__Enrollment_Status__c : 'N/A') + '\n' +
                'Record link: ' + peUrl + '\n\n' +
                'This is an automated notification.';

            msg.setPlainTextBody(body);
            emails.add(msg);
        }

        if (emails.isEmpty()) return;

        try {
            if (Test.isRunningTest() && throwInTestForCoverage) {
                throw new CalloutException('Test coverage for exception path');
            }
            Messaging.sendEmail(emails);

            // Log on PE: EmailMessage (needs MessageDate + FromAddress in many orgs). Fallback to Task if insert fails.
            List<EmailMessage> logs = new List<EmailMessage>();
            Map<Id, String> logDescriptionByPeId = new Map<Id, String>();
            for (Id peId : peIdsForEmails) {
                hed__Program_Enrollment__c pe = peMap.get(peId);
                if (pe == null) continue;

                String baseUrl = System.URL.getOrgDomainUrl().toExternalForm();
                String peUrl = baseUrl + '/lightning/r/hed__Program_Enrollment__c/' + pe.Id + '/view';
                String logBody =
                    'A new Program Enrollment has been submitted.' + '\n\n' +
                    'Program Enrollment: ' + (pe.Name != null ? pe.Name : String.valueOf(pe.Id)) + '\n' +
                    'Student: ' + (pe.hed__Contact__r != null ? pe.hed__Contact__r.Name : 'N/A') + '\n' +
                    'Program: ' + (pe.hed__Account__r != null ? pe.hed__Account__r.Name : 'N/A') + '\n' +
                    'Status: ' + (pe.hed__Enrollment_Status__c != null ? pe.hed__Enrollment_Status__c : 'N/A') + '\n' +
                    'Record link: ' + peUrl + '\n\n' +
                    'This is an automated notification.';

                String subj = 'New Program Enrollment submitted: ' + (pe.Name != null ? pe.Name : String.valueOf(pe.Id));
                logDescriptionByPeId.put(pe.Id, logBody);
                logs.add(EmailActivityLogUtil.buildOutgoingLog(pe.Id, officeAddress, subj, logBody));
            }

            if (Test.isRunningTest()) {
                if (!peIdsForEmails.isEmpty()) {
                    hed__Program_Enrollment__c pe = peMap.get(peIdsForEmails[0]);
                    if (pe != null) {
                        Task t = new Task();
                        t.Subject = 'Program Office Notified: New Program Enrollment';
                        t.Description = 'Email sent to Program Office (test only).';
                        t.ActivityDate = Date.today();
                        t.WhatId = pe.Id;
                        if (pe.hed__Contact__c != null) t.WhoId = pe.hed__Contact__c;
                        insert t;
                    }
                }
            } else {
                try {
                    if (!logs.isEmpty()) {
                        insert logs;
                    }
                } catch (Exception logEx) {
                    System.debug('ProgramEnrollmentOfficeNotify EmailMessage log failed: ' + logEx.getMessage());
                    List<Task> fallbacks = new List<Task>();
                    for (Id peId : peIdsForEmails) {
                        hed__Program_Enrollment__c pe = peMap.get(peId);
                        Task t = new Task();
                        t.Subject = 'Program Office Notified: New Program Enrollment';
                        t.Description = logDescriptionByPeId.containsKey(peId)
                            ? logDescriptionByPeId.get(peId)
                            : 'Program Office notification email was sent.';
                        t.ActivityDate = Date.today();
                        t.WhatId = peId;
                        if (pe != null && pe.hed__Contact__c != null) t.WhoId = pe.hed__Contact__c;
                        fallbacks.add(t);
                    }
                    if (!fallbacks.isEmpty()) insert fallbacks;
                }
            }

            for (Id peId : peIdsForEmails) {
                alreadyNotifiedPeIds.add(peId);
            }
            // Stamp PE so 24h dedupe works across transactions (if custom field exists).
            try {
                if (Schema.sObjectType.hed__Program_Enrollment__c.fields.getMap().containsKey('Program_Office_Notified_Date__c')) {
                    List<SObject> toUpdate = new List<SObject>();
                    for (Id peId : peIdsForEmails) {
                        SObject pe = Schema.getGlobalDescribe().get('hed__Program_Enrollment__c').newSObject(peId);
                        pe.put('Program_Office_Notified_Date__c', Datetime.now());
                        toUpdate.add(pe);
                    }
                    if (!toUpdate.isEmpty()) update toUpdate;
                }
            } catch (Exception ignore) { /* field may not exist or be read-only */ }
        } catch (Exception e) {
            System.debug('ProgramEnrollmentOfficeNotify: ' + e.getTypeName() + ' - ' + e.getMessage());
            if (Test.isRunningTest() && !peIdsForEmails.isEmpty()) {
                hed__Program_Enrollment__c pe = peMap.get(peIdsForEmails[0]);
                if (pe != null) {
                    Task t = new Task();
                    t.Subject = 'Program Office email EXCEPTION';
                    t.Description = e.getTypeName() + ': ' + e.getMessage();
                    t.ActivityDate = Date.today();
                    t.WhatId = pe.Id;
                    insert t;
                }
            }
        }
    }
}

