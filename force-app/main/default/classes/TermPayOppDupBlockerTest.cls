@isTest
private class TermPayOppDupBlockerTest {
    private class Fixture {
        public Term_Enrollment__c te;
        public Id accountId;
    }

    private static Id termPaymentRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> infos = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
        System.assert(infos.containsKey('Term_Payment'), 'Term_Payment Opportunity record type required for this org.');
        return infos.get('Term_Payment').getRecordTypeId();
    }

    private static Fixture createFixture() {
        Account acct = new Account(Name = 'DupBlocker Program');
        insert acct;
        Contact con = new Contact(FirstName = 'Dup', LastName = 'Blocker', AccountId = acct.Id);
        insert con;
        hed__Program_Enrollment__c pe = new hed__Program_Enrollment__c(
            hed__Account__c = acct.Id,
            hed__Contact__c = con.Id,
            hed__Enrollment_Status__c = 'Currently Enrolled'
        );
        insert pe;
        Term_Enrollment__c te = new Term_Enrollment__c(
            Name = 'DupBlocker TE',
            Program_Enrollment__c = pe.Id
        );
        insert te;
        Fixture f = new Fixture();
        f.te = te;
        f.accountId = acct.Id;
        return f;
    }

    private static Opportunity baseOpp(Id teId, Id accountId, String faUrl) {
        Opportunity o = new Opportunity(
            Name = 'Payment Test Opp',
            AccountId = accountId,
            StageName = 'Payment Due',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = termPaymentRecordTypeId(),
            Term_Enrollment__c = teId
        );
        if (String.isNotBlank(faUrl)) {
            o.FA_Response_URL__c = faUrl;
        }
        return o;
    }

    @isTest
    static void allowsSingleNoFaRow() {
        Fixture f = createFixture();
        Opportunity o = baseOpp(f.te.Id, f.accountId, null);
        insert o;
        System.assertNotEquals(null, o.Id);
    }

    @isTest
    static void blocksSecondNoFaAfterFirstCommitted() {
        Fixture f = createFixture();
        insert baseOpp(f.te.Id, f.accountId, null);
        Opportunity duplicate = baseOpp(f.te.Id, f.accountId, null);
        try {
            insert duplicate;
            System.assert(false, 'Expected DmlException');
        } catch (DmlException expected) {
            System.assert(
                expected.getMessage().contains('FA Response URL') || expected.getMessage().contains('second'),
                expected.getMessage()
            );
        }
    }

    @isTest
    static void batchFaRowBlocksNoFaSiblingSameTe() {
        Fixture f = createFixture();
        List<Opportunity> rows = new List<Opportunity>{
            baseOpp(f.te.Id, f.accountId, 'https://example.com/fa/123'),
            baseOpp(f.te.Id, f.accountId, null)
        };
        Database.SaveResult[] results = Database.insert(rows, false);
        System.assert(results[0].isSuccess(), results[0].getErrors().toString());
        System.assert(!results[1].isSuccess(), 'Second no-FA row should fail when FA row is in same batch.');
    }

    @isTest
    static void faInsertRemovesPriorNoFaOppForSameTe() {
        Fixture f = createFixture();
        insert baseOpp(f.te.Id, f.accountId, null);
        Opportunity faRow = baseOpp(f.te.Id, f.accountId, 'https://example.com/fa/999');
        faRow.Name = 'Payment Test Opp FA';
        insert faRow;
        List<Opportunity> remaining = [
            SELECT Id, FA_Response_URL__c
            FROM Opportunity
            WHERE Term_Enrollment__c = :f.te.Id
        ];
        System.assertEquals(1, remaining.size(), 'FA insert should replace the no-FA orphan.');
        System.assert(String.isNotBlank(remaining[0].FA_Response_URL__c));
    }
}
