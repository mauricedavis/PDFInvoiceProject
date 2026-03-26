public with sharing class ProgramEnrollmentNotificationActions {

    // Wrapper for Flow input
    public class ProgramEnrollmentRequest {
        @InvocableVariable(required=true)
        public Id programEnrollmentId;
    }

    private class ResponseDoc {
        public String title;
        public Blob body;
        public Id contentDocumentId; // present when sourced from Files
    }

    private static Task buildEmailTask(Id peId, Id contactId, String subject, String body) {
        if (peId == null && contactId == null) return null;
        Task t = new Task();
        t.Subject = subject;
        t.Description = body;
        t.ActivityDate = Date.today();
        if (contactId != null) t.WhoId = contactId;
        if (peId != null) t.WhatId = peId;
        return t;
    }

    private static ResponseDoc getLatestResponsesPdfFromContact(Id contactId) {
        if (contactId == null) return null;

        // 1) Prefer a File (ContentVersion) linked to the Contact
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.FileType
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contactId
              AND ContentDocument.FileType = 'PDF'
              AND (
                   ContentDocument.Title LIKE '%Course Registration%'
                OR ContentDocument.Title LIKE '%Registration%'
                OR ContentDocument.Title LIKE '%Response%'
                OR ContentDocument.Title LIKE '%Responses%'
              )
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];

        if (!links.isEmpty()) {
            ContentVersion cv = [
                SELECT Id, Title, VersionData, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
                LIMIT 1
            ];

            ResponseDoc r = new ResponseDoc();
            r.title = cv.Title;
            r.body = cv.VersionData;
            r.contentDocumentId = cv.ContentDocumentId;
            return r;
        }

        // 2) Fallback: classic Attachment on the Contact (FormAssembly often uses this)
        List<Attachment> atts = [
            SELECT Id, Name, Body, ContentType
            FROM Attachment
            WHERE ParentId = :contactId
              AND (ContentType LIKE 'application/pdf%' OR Name LIKE '%.pdf' OR Name LIKE '%.PDF')
              AND (
                   Name LIKE '%Course Registration%'
                OR Name LIKE '%Registration%'
                OR Name LIKE '%Response%'
                OR Name LIKE '%Responses%'
              )
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (atts.isEmpty()) return null;

        ResponseDoc a = new ResponseDoc();
        a.title = atts[0].Name;
        a.body = atts[0].Body;
        a.contentDocumentId = null;
        return a;
    }

    private static void ensureFileLinkedToProgramEnrollment(Id peId, Id contentDocumentId) {
        if (peId == null || contentDocumentId == null) return;

        Integer existing = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :peId
              AND ContentDocumentId = :contentDocumentId
        ];
        if (existing > 0) return;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = contentDocumentId;
        cdl.LinkedEntityId = peId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }

    private static Id ensureResponsesFileOnProgramEnrollment(Id peId, Id contactId, ResponseDoc responseDoc) {
        if (peId == null || responseDoc == null || responseDoc.body == null) return null;

        // If the responses doc is already a File, just link it to the PE.
        if (responseDoc.contentDocumentId != null) {
            ensureFileLinkedToProgramEnrollment(peId, responseDoc.contentDocumentId);
            return responseDoc.contentDocumentId;
        }

        // If it came from an Attachment, create a File on the PE (and optionally also link to the Contact).
        String title = String.isBlank(responseDoc.title) ? 'Form Responses' : responseDoc.title;
        String fileName = title.toLowerCase().endsWith('.pdf') ? title : (title + '.pdf');

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName.endsWith('.pdf') ? fileName.left(fileName.length() - 4) : fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = responseDoc.body;
        cv.IsMajorVersion = true;
        cv.FirstPublishLocationId = peId;
        insert cv;

        Id docId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
            LIMIT 1
        ].ContentDocumentId;

        // Optional: also link this new File back to the Contact for consistency
        if (contactId != null) {
            ensureFileLinkedToProgramEnrollment(contactId, docId);
        }

        return docId;
    }

    // ===== 1) Enrollee confirmation (template-based, with safe fallback) =====
    @InvocableMethod(
        label='Send Program Enrollment Confirmation Email'
        description='Sends a confirmation email to the Program Enrollment contact using the ucsf-prod template (DeveloperName from ProgramEnrollmentEmailTemplateConfig) when active; otherwise inline body.'
    )
    public static void sendEnrollmentConfirmation(List<ProgramEnrollmentRequest> requests) {
        if (requests == null || requests.isEmpty()) return;

        Set<Id> peIds = new Set<Id>();
        for (ProgramEnrollmentRequest r : requests) {
            if (r != null && r.programEnrollmentId != null) {
                peIds.add(r.programEnrollmentId);
            }
        }
        if (peIds.isEmpty()) return;

        // Load Program Enrollments + Contacts
        Map<Id, hed__Program_Enrollment__c> peMap = new Map<Id, hed__Program_Enrollment__c>(
            [
                SELECT Id,
                       Name,
                       hed__Contact__c,
                       hed__Contact__r.Name,
                       hed__Contact__r.Email,
                       hed__Account__r.Name
                FROM hed__Program_Enrollment__c
                WHERE Id IN :peIds
            ]
        );

        if (peMap.isEmpty()) return;

        Id templateId = ProgramEnrollmentEmailTemplateConfig.getActiveStudentConfirmationTemplateId();

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> peIdsForEmails = new List<Id>();
        List<Id> contactIdsForEmails = new List<Id>();
        List<Task> tasksToInsert = new List<Task>();

        for (Id peId : peIds) {
            hed__Program_Enrollment__c pe = peMap.get(peId);
            if (pe == null ||
                pe.hed__Contact__c == null ||
                pe.hed__Contact__r == null ||
                String.isBlank(pe.hed__Contact__r.Email)) {
                continue;
            }

            // Pull latest responses PDF from Contact and link it to the Program Enrollment for audit trail.
            ResponseDoc responseDoc = getLatestResponsesPdfFromContact(pe.hed__Contact__c);
            ensureResponsesFileOnProgramEnrollment(pe.Id, pe.hed__Contact__c, responseDoc);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            // Use target object so the email can be logged to the Contact and related to the Program Enrollment.
            msg.setTargetObjectId(pe.hed__Contact__c);
            msg.setWhatId(pe.Id);
            msg.setTreatTargetObjectAsRecipient(true);

            if (templateId != null) {
                msg.setTemplateId(templateId);
                msg.setSaveAsActivity(true);
            } else {
                // Fallback inline message if template is not available
                msg.setSubject('Your Program Enrollment Confirmation');
                String body =
                    'Hello ' + pe.hed__Contact__r.Name + ',\n\n' +
                    'Thank you for enrolling in ' + (pe.hed__Account__r != null ? pe.hed__Account__r.Name : 'our program') + '.\n\n' +
                    'Your Program Enrollment record has been received and is being processed.\n\n' +
                    'Thank you,\n' +
                    'Implementation Science Training Program';
                msg.setPlainTextBody(body);
                msg.setSaveAsActivity(true);
            }

            // Attach the responses PDF to the confirmation email when available.
            if (responseDoc != null && responseDoc.body != null) {
                Messaging.EmailFileAttachment efa = new Messaging.EmailFileAttachment();
                String respTitle = String.isBlank(responseDoc.title) ? 'Form_Responses.pdf' : responseDoc.title;
                efa.setFileName(respTitle.toLowerCase().endsWith('.pdf') ? respTitle : (respTitle + '.pdf'));
                efa.setBody(responseDoc.body);
                efa.setContentType('application/pdf');
                msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ efa });
            }

            emails.add(msg);
            peIdsForEmails.add(pe.Id);
            contactIdsForEmails.add(pe.hed__Contact__c);

            // Also log an explicit Activity to ensure visibility on both PE and Contact related lists.
            // (Some orgs may have Enhanced Email nuances; this guarantees a record is created.)
            String taskSubject = (templateId != null)
                ? 'Program Enrollment Confirmation Sent'
                : 'Program Enrollment Confirmation Sent (Fallback)';
            String taskBody = 'Confirmation email sent to: ' + pe.hed__Contact__r.Email +
                (responseDoc != null ? '\nAttached: ' + responseDoc.title : '\n(No responses PDF found to attach)');

            Task t = buildEmailTask(pe.Id, pe.hed__Contact__c, taskSubject, taskBody);
            if (t != null) tasksToInsert.add(t);
        }

        if (!tasksToInsert.isEmpty()) {
            insert tasksToInsert;
        }

        if (!emails.isEmpty()) {
            List<Task> errorTasks = new List<Task>();
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emails);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        String errMsg = '';
                        for (Messaging.SendEmailError e : results[i].getErrors()) {
                            errMsg += e.getStatusCode() + ': ' + e.getMessage() + '; ';
                        }
                        Task errTask = buildEmailTask(
                            peIdsForEmails[i],
                            contactIdsForEmails[i],
                            'Confirmation email FAILED',
                            errMsg
                        );
                        if (errTask != null) errorTasks.add(errTask);
                    }
                }
                if (!errorTasks.isEmpty()) insert errorTasks;
            } catch (Exception e) {
                for (Integer i = 0; i < peIdsForEmails.size(); i++) {
                    Task errTask = buildEmailTask(
                        peIdsForEmails[i],
                        contactIdsForEmails[i],
                        'Confirmation email EXCEPTION',
                        e.getTypeName() + ': ' + e.getMessage()
                    );
                    if (errTask != null) errorTasks.add(errTask);
                }
                if (!errorTasks.isEmpty()) insert errorTasks;
            }
        }
    }
}

