@isTest
public class TransactionViewerTest {

    //
    // Helper wrapper so we can return both the User + FCC
    //
    private class TestContext {
        User u;
        UHN_FCC__c fcc;
    }

    //
    // Create a valid User + Contact + FCC, and return both User + FCC
    //
    private static TestContext createContext() {

        TestContext ctx = new TestContext();

        // Create User
        User u = new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = 'tusr',
            Username = 'testuser' + DateTime.now().getTime() + '@test.com',
            Email = 'testuser' + DateTime.now().getTime() + '@test.com',
            TimeZoneSidKey = 'America/Toronto',
            LocaleSidKey = 'en_CA',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id
        );
        insert u;

        // Create Contact linked to the User
        Contact c = new Contact(
            LastName = 'FCC Contact',
            UHN_User__c = u.Id
        );
        insert c;

        // Create valid FCC
        // IMPORTANT: UHN_Name__c is referenced in TransactionItem and startsWith() is called on it.
        // Setting it prevents null pointer exceptions and makes the label logic deterministic.
        String fccName = 'FCC-' + DateTime.now().getTime();

        UHN_FCC__c f = new UHN_FCC__c(
            Name = fccName,
            UHN_Name__c = fccName + ' - Test FCC', // ✅ prevent null + matches startsWith(fccNumber)
            UHN_Contact__c = c.Id,
            UHN_FCC_Status__c = 'Open',
            UHN_FCC_Type_long__c = 'Grant Internal Order',
            UHN_NonSalary_Actuals_Allowed__c = 'Yes',
            UHN_To_be_Closed__c = false,
            UHN_Blocked__c = false
        );
        insert f;

        ctx.u = u;
        ctx.fcc = f;

        return ctx;
    }

    //
    // Backward-compatible helper — returns only FCC like before
    //
    private static UHN_FCC__c createFCC() {
        return createContext().fcc;
    }

    // Create GL Account
    private static UHN_GL_Account__c createGL() {
        UHN_GL_Account__c gl = new UHN_GL_Account__c(
            Name = '600001',
            UHN_PI_Expense_or_Revenue_Type__c = 'Equipment',
            UHN_Cost_Element_Description__c = 'Test Desc',
            UHN_SAP_ID__c = 'SAPTEST001' // ⭐ REQUIRED FIELD
        );
        insert gl;
        return gl;
    }

    // Create Journal Entry (NO formula fields included)
    private static UHN_Journal_Entry__c createJE(Id fccId, Id glId) {
        UHN_Journal_Entry__c je = new UHN_Journal_Entry__c(
            Name = 'JE-Test-' + DateTime.now().getTime(),
            UHN_FCC__c = fccId,
            UHN_GL_Account__c = glId,
            UHN_PI_Expense_or_Revenue_Class__c = 'Expense',
            UHN_PI_Expense_or_Revenue_Type__c = 'Equipment',
            UHN_Debit_or_Credit__c = 'Debit',
            UHN_UID__c = 'UID-' + Math.abs(Crypto.getRandomLong()),
            UHN_Calculated_Date_Key__c = Date.today(),

            // ✅ KEY CHANGE:
            // UHN_Actual_Amount__c is read-only and calculated.
            // In many orgs, Debit makes Actual negative (via sign logic),
            // so we set Amount positive so Actual computes negative.
            UHN_Amount__c = 10
        );

        insert je;
        return je;
    }

    @isTest
    static void testGetTransactions() {
        UHN_FCC__c fcc = createFCC();
        UHN_GL_Account__c gl = createGL();
        createJE(fcc.Id, gl.Id);

        Test.startTest();
        Map<String, Object> result = TransactionViewer.getTransactions();
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetTransactionsRD() {
        // ✅ Use context so we can run as the user tied to the FCC contact
        TestContext ctx = createContext();
        UHN_GL_Account__c gl = createGL();
        createJE(ctx.fcc.Id, gl.Id);

        System.runAs(ctx.u) {
            Test.startTest();
            Map<String, Object> rdResult = TransactionViewer.getTransactionsRD(ctx.fcc.Id);
            Test.stopTest();

            System.assertNotEquals(null, rdResult);
        }
    }

    @isTest
    static void testSearchGLByCategory() {
        Set<String> pool = new Set<String>{ 'Equipment' };

        List<Map<String, Object>> results =
            TransactionViewer.searchGLByCategory('Equip', JSON.serialize(pool));

        System.assert(results.size() > 0, 'Expected at least one match');
    }

    @isTest
    static void testMonthPeriods() {
        System.assertNotEquals(null,
            TransactionViewer.getDatePickerMonthPeriod('currentMonth'));

        System.assertNotEquals(null,
            TransactionViewer.getDatePickerMonthPeriod('previousMonth'));
    }

    @isTest
    static void testRangePeriods() {
        System.assertNotEquals(null,
            TransactionViewer.getDatePickerRangePeriod('quarter', 0));

        System.assertNotEquals(null,
            TransactionViewer.getDatePickerRangePeriod('year', 0));
    }

    @isTest
    static void testFields() {
        System.assertNotEquals(null, TransactionViewer.getTranscationFields(true));
        System.assertNotEquals(null, TransactionViewer.getTranscationFields(false));
    }

    @isTest
    static void testCanViewSalaries() {
        System.assertEquals(true, TransactionViewer.canViewSalaries());
    }
}