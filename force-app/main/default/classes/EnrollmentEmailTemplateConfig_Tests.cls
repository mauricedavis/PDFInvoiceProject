@IsTest
private class EnrollmentEmailTemplateConfig_Tests {

    @IsTest
    static void test_GetActiveStudentConfirmationTemplateId_usesCacheAndReset() {
        ProgramEnrollmentEmailTemplateConfig.resetStudentConfirmationTemplateCacheForTest();
        Id first = ProgramEnrollmentEmailTemplateConfig.getActiveStudentConfirmationTemplateId();
        Id second = ProgramEnrollmentEmailTemplateConfig.getActiveStudentConfirmationTemplateId();
        System.assertEquals(first, second, 'Cached Id should match immediate repeat call.');

        ProgramEnrollmentEmailTemplateConfig.resetStudentConfirmationTemplateCacheForTest();
        Id afterReset = ProgramEnrollmentEmailTemplateConfig.getActiveStudentConfirmationTemplateId();
        System.assertEquals(first, afterReset, 'After reset, SOQL should resolve the same template (or both null).');
    }

    @IsTest
    static void test_IsAd_HocClinicalResearchProgram_by_account_name_or_id_production_alignment() {
        Account adHoc = new Account(Name = 'Ad Hoc Clinical Research Course program');
        insert adHoc;
        Boolean byNameOnly = ProgramEnrollmentEmailTemplateConfig.isAdHocClinicalResearchProgram(null, adHoc.Name);
        Boolean bySandboxName = ProgramEnrollmentEmailTemplateConfig.isAdHocClinicalResearchProgram(adHoc.Id, 'Some unrelated name');
        System.assertEquals(true, byNameOnly, 'Name match should classify Ad Hoc.');
        System.assertEquals(false, bySandboxName, 'Different sandbox Account Id alone should not match prod Id.');
    }

    @IsTest
    static void test_Resolve_templates_match_implementation_when_org_has_no_rows() {
        ProgramEnrollmentEmailTemplateConfig.resetStudentConfirmationTemplateCacheForTest();
        Set<Id> bundled = ProgramEnrollmentEmailTemplateConfig.allActiveStudentConfirmationTemplateIds();
        System.assertNotEquals(null, bundled);

        Account iso = new Account(Name = 'Online Certificate in Implementation Science');
        insert iso;
        Id isTpl = ProgramEnrollmentEmailTemplateConfig.getActiveStudentConfirmationTemplateId();
        Id resolvedIs = ProgramEnrollmentEmailTemplateConfig.resolveStudentConfirmationTemplateId(iso.Id, iso.Name);
        System.assertEquals(isTpl, resolvedIs);

        Account adHocAcct = new Account(Name = 'Ad Hoc Clinical Research Course program sandbox');
        insert adHocAcct;
        Id debTpl = ProgramEnrollmentEmailTemplateConfig.getActiveAdHocDebStudentConfirmationTemplateId();
        Id resolvedAdHoc = ProgramEnrollmentEmailTemplateConfig.resolveStudentConfirmationTemplateId(
            adHocAcct.Id,
            adHocAcct.Name
        );
        if (bundled.isEmpty()) {
            System.assertEquals(null, resolvedAdHoc, 'Sandbox without deployed templates resolves null.');
        } else if (debTpl != null) {
            System.assertEquals(debTpl, resolvedAdHoc, 'Deployed DEB template should win for Ad Hoc match.');
        } else {
            System.assertEquals(isTpl, resolvedAdHoc, 'Absent DEB falls back to IS template when deployed.');
        }
    }
}
