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
}
