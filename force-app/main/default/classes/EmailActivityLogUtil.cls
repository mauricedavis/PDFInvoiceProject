/**
 * Builds EmailMessage rows for Activity Timeline on related records.
 * Salesforce PDF / some orgs need MessageDate + FromAddress for inserts to succeed.
 */
public with sharing class EmailActivityLogUtil {

    public static String resolveFromAddressForLogs() {
        try {
            List<OrgWideEmailAddress> o = [
                SELECT Address
                FROM OrgWideEmailAddress
                WHERE IsVerified = true
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            if (!o.isEmpty() && !String.isBlank(o[0].Address)) {
                return o[0].Address;
            }
        } catch (Exception ignore) { }
        return UserInfo.getUserEmail();
    }

    public static EmailMessage buildOutgoingLog(Id relatedToId, String toAddress, String subject, String textBody) {
        EmailMessage em = new EmailMessage();
        em.RelatedToId = relatedToId;
        em.ToAddress = toAddress;
        em.FromAddress = resolveFromAddressForLogs();
        em.Subject = subject;
        em.TextBody = textBody;
        em.MessageDate = Datetime.now();
        em.Status = '3';
        em.Incoming = false;
        return em;
    }
}
