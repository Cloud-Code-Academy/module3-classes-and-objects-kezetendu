// Retrieves all debit sided transactions for transaction into a target FCC.
// Debit sided transactions have a negative UHN_Actual_Amount__c value
public with sharing class TransactionViewer {

    static Set<String> glCategoryList = new Set<String>{'Equipment', 'Supplies and Other', 'Travel', 'Animal'};
    static Map<Integer, String> monthsMap = new Map<Integer, String>{
        1 => 'Jan', 2 => 'Feb', 3 => 'Mar', 4 => 'Apr', 5 => 'May', 6 => 'Jun',
        7 => 'Jul', 8 => 'Aug', 9 => 'Sep', 10 => 'Oct', 11 => 'Nov', 12 => 'Dec'
    };
    static Map<String, Schema.SObjectField> transactionFieldsMap =
        UHN_Journal_Entry__c.sObjectType.getDescribe().fields.getmap();

    static Set<String> jeTypeAllowList = new Set<String>{
        'INTEGER', 'DOUBLE', 'LONG', 'CURRENCY', 'STRING', 'PICKLIST', 'ID', 'REFERENCE'
    };

    static Set<String> jeFieldBlockList = new Set<String>{
        'isdeleted', 'createddate', 'uhn_calculated_date_key__c', 'uhn_gl_account__c', 'uhn_amount__c',
        'uhn_display_sign_multiplier__c', 'uhn_previous_month__c', 'uhn_previous_6_months__c'
    };

    // Note: this query runs at class load time; keep as-is since it existed already.
    static User contextUser = [SELECT Id, ContactId FROM User WHERE Id = :UserInfo.getUserId()];

    public class OutdatedTransactionException extends Exception {}

    @AuraEnabled(cacheable=true)
    public static Boolean canViewSalaries() {
        try {
            return true;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Retrieve all expense transfer records
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getTransactions() {
        try {
            Map<Id, TransactionItem> transactionMap = new Map<Id, TransactionItem>();
            Map<String, Object> searchPoolMap = new Map<String, Object>();
            Set<Id> fccIDs = new Set<Id>();
            Set<Id> glIDs = new Set<Id>();
            Set<String> glCategories = new Set<String>();

            // Get all transaction IDs
            Map<Id, UHN_Journal_Entry__c> journalEntryIDs = new Map<Id, UHN_Journal_Entry__c>(
                [SELECT Id
                 FROM UHN_Journal_Entry__c
                 WHERE UHN_PI_Expense_or_Revenue_Class__c = 'Expense'
                   AND UHN_FCC__r.UHN_FCC_Status__c = 'Open'
                   AND UHN_PI_Expense_or_Revenue_Type__c IN :TransactionViewer.glCategoryList
                   AND UHN_Actual_Amount__c < 0
                   AND UHN_Debit_or_Credit__c = 'Debit'
                   AND (NOT Name LIKE 't/f %')
                   AND (NOT Name LIKE 'ptf %')
                 LIMIT 0]
            );

            // ✅ Guard: don't call WOS with an empty set
            if (journalEntryIDs.isEmpty()) {
                return new Map<String, Object>{
                    'transactionMap' => new Map<Id, TransactionItem>(),
                    'searchPoolMap' => new Map<String, Object>{
                        'transactionIDs' => new Set<Id>(),
                        'fccIDs' => new Set<Id>(),
                        'glIDs' => new Set<Id>(),
                        'glCategories' => new Set<String>()
                    },
                    'canViewUnavailableTransactions' => false
                };
            }

            // transactionIDs without sharing applied
            List<UHN_Journal_Entry__c> journalEntriesWOS =
                TransactionViewerWOS.getTransactions(journalEntryIDs.keySet());

            // Retrieve the transaction map
            for (UHN_Journal_Entry__c je : journalEntriesWOS) {
                transactionMap.put(je.Id, new TransactionItem(je));
                fccIDs.add(je.UHN_FCC__c);
                glIDs.add(je.UHN_GL_Account__c);
                glCategories.add(je.UHN_GL_Account__r.UHN_PI_Expense_or_Revenue_Type__c);
            }

            // Adding search pools
            searchPoolMap.put('transactionIDs', transactionMap.keySet());
            searchPoolMap.put('fccIDs', fccIDs);
            searchPoolMap.put('glIDs', glIDs);
            searchPoolMap.put('glCategories', glCategories);

            return new Map<String, Object>{
                'transactionMap' => transactionMap,
                'searchPoolMap' => searchPoolMap,
                'canViewUnavailableTransactions' => false
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Retrieve all expense transfer records that a user has access to
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getTransactionsRD(String recordId) {
        try {
            Set<Id> recordIdFormatted = new Set<Id>{ (Id)recordId };
            Map<Id, UHN_Journal_Entry__c> journalEntryIDs;
            Map<Id, TransactionItem> transactionMap = new Map<Id, TransactionItem>();
            Map<String, Object> searchPoolMap = new Map<String, Object>();
            Set<Id> fccIDs = new Set<Id>();
            Set<Id> glIDs = new Set<Id>();
            Set<String> glCategories = new Set<String>();

            // Unavailable transactions have a transfer amount of 0$
            Boolean canViewUnavailableTransactions =
                FeatureManagement.checkPermission('ETM_View_Unavailable_Transactions');

            if (canViewUnavailableTransactions) {
                journalEntryIDs = new Map<Id, UHN_Journal_Entry__c>(
                    [SELECT Id
                     FROM UHN_Journal_Entry__c
                     WHERE UHN_FCC__c IN :recordIdFormatted
                       AND UHN_FCC__r.UHN_FCC_Status__c = 'Open'
                       AND UHN_PI_Expense_or_Revenue_Class__c = 'Expense'
                       AND UHN_PI_Expense_or_Revenue_Type__c IN :TransactionViewer.glCategoryList
                       AND UHN_Actual_Amount__c <= 0
                       AND UHN_Debit_or_Credit__c = 'Debit'
                       AND (NOT Name LIKE 't/f %')
                       AND (NOT Name LIKE 'ptf %')]
                );
            } else {
                journalEntryIDs = new Map<Id, UHN_Journal_Entry__c>(
                    [SELECT Id
                     FROM UHN_Journal_Entry__c
                     WHERE UHN_FCC__c IN :recordIdFormatted
                       AND UHN_FCC__r.UHN_FCC_Status__c = 'Open'
                       AND UHN_PI_Expense_or_Revenue_Class__c = 'Expense'
                       AND UHN_PI_Expense_or_Revenue_Type__c IN :TransactionViewer.glCategoryList
                       AND UHN_Actual_Amount__c < 0
                       AND UHN_Debit_or_Credit__c = 'Debit'
                       AND (NOT Name LIKE 't/f %')
                       AND (NOT Name LIKE 'ptf %')]
                );
            }

            // ✅ Guard: don't call WOS with an empty set
            if (journalEntryIDs.isEmpty()) {
                return new Map<String, Object>{
                    'transactionMap' => new Map<Id, TransactionItem>(),
                    'searchPoolMap' => new Map<String, Object>{
                        'transactionIDs' => new Set<Id>(),
                        'fccIDs' => new Set<Id>(),
                        'glIDs' => new Set<Id>(),
                        'glCategories' => new Set<String>()
                    },
                    'canViewUnavailableTransactions' => canViewUnavailableTransactions
                };
            }

            // transactionIDs without sharing applied
            List<UHN_Journal_Entry__c> journalEntriesWOS =
                TransactionViewerWOS.getTransactionsRD(journalEntryIDs.keySet());

            // Retrieve the transaction map
            for (UHN_Journal_Entry__c je : journalEntriesWOS) {
                transactionMap.put(je.Id, new TransactionItem(je));
                fccIDs.add(je.UHN_FCC__c);
                glIDs.add(je.UHN_GL_Account__c);
                glCategories.add(je.UHN_GL_Account__r.UHN_PI_Expense_or_Revenue_Type__c);
            }

            // Adding search pools
            searchPoolMap.put('transactionIDs', transactionMap.keySet());
            searchPoolMap.put('fccIDs', fccIDs);
            searchPoolMap.put('glIDs', glIDs);
            searchPoolMap.put('glCategories', glCategories);

            return new Map<String, Object>{
                'transactionMap' => transactionMap,
                'searchPoolMap' => searchPoolMap,
                'canViewUnavailableTransactions' => canViewUnavailableTransactions
            };
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Used to return typeahead search results based on GL category (transaction type)
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> searchGLByCategory(String textInput, String searchPool) {
        try {
            List<String> glCategory = (List<String>)JSON.deserialize(searchPool, List<String>.class);
            List<Map<String, Object>> mapList = new List<Map<String, Object>>();
            Integer matches = 0;

            for (Integer i = 0; i < glCategory.size() && matches < 5; i++) {
                String textEntity = glCategory[i];
                if (textEntity != null && textEntity.containsIgnoreCase(textInput)) {
                    String textEntityHTML = TransactionViewer.highlightMatchedText(textEntity, textInput);
                    mapList.add(new Map<String, Object>{
                        'textEntity' => textEntity,
                        'textEntityHTML' => textEntityHTML,
                        'textMeta' => '',
                        'textMetaHTML' => null,
                        'id' => glCategory[i]
                    });
                    matches++;
                }
            }
            return mapList;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Highlights matched text in a string
    public static String highlightMatchedText(String str, String textInput) {
        Integer matchStartIndex = str.toLowerCase().indexOf(textInput.toLowerCase());
        Integer matchLastIndex = matchStartIndex + textInput.length() - 1;
        String replacement = '<mark>' + str.substring(matchStartIndex, matchLastIndex + 1) + '</mark>';
        String textEntityHTML =
            str.substring(0, matchStartIndex) + replacement + str.substring(matchLastIndex + 1);
        return textEntityHTML;
    }

    // Gets the first and last date for today's month and the one prior
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getDatePickerMonthPeriod(String periodType) {
        try {
            Map<String, String> dateMap = new Map<String, String>();
            Date todaysDate = System.today();

            if (periodType.equalsIgnoreCase('previousMonth')) {
                Integer prevMonthNum = (todaysDate.month() - 1 > 0) ? todaysDate.month() - 1 : 12;
                dateMap = TransactionViewer.getStartAndEndDate(todaysDate.year(), prevMonthNum, todaysDate.day());
            } else if (periodType.equalsIgnoreCase('currentMonth')) {
                dateMap = TransactionViewer.getStartAndEndDate(todaysDate.year(), todaysDate.month(), todaysDate.day());
            }

            return dateMap;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Retrieves the start and last date for a given month
    public static Map<String, String> getStartAndEndDate(Integer year, Integer month, Integer day) {
        Integer daysInMonth = Date.daysInMonth(year, month);
        Date firstDateOfMonth = Date.newInstance(year, month, daysInMonth).toStartOfMonth();
        Date lastDateOfMonth = Date.newInstance(year, month, daysInMonth);
        return new Map<String, String>{
            'firstDateOfMonth' => firstDateOfMonth.format(),
            'lastDateOfMonth' => lastDateOfMonth.format()
        };
    }

    // Gets the first and last date for a quarter or year
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getDatePickerRangePeriod(String periodType, Integer n) {
        try {
            Map<String, String> dateMap = new Map<String, String>();
            Date todaysDate = System.today();
            Date firstDateOfMonth;
            Date lastDateOfMonth;

            if (periodType.equalsIgnoreCase('quarter')) {
                Date nQuartersAgo = todaysDate.addMonths(-n * 3);
                Integer currentQuarter = TransactionViewer.findQuarter(nQuartersAgo);
                Integer todaysQuarter = TransactionViewer.findQuarter(todaysDate);

                Integer quarterStartMonth = currentQuarter * 3 - 2;
                Integer quarterEndMonth = currentQuarter * 3;
                Boolean isSameQuarterDate =
                    currentQuarter == todaysQuarter && nQuartersAgo.year() == todaysDate.year();

                firstDateOfMonth = Date.newInstance(nQuartersAgo.year(), quarterStartMonth, 1).toStartOfMonth();
                lastDateOfMonth = !isSameQuarterDate
                    ? Date.newInstance(nQuartersAgo.year(), quarterEndMonth, Date.daysInMonth(nQuartersAgo.year(), quarterEndMonth))
                    : todaysDate;

            } else if (periodType.equalsIgnoreCase('year')) {
                Integer y = todaysDate.year() - n;
                Boolean isSameYear = (n == 0);

                firstDateOfMonth = Date.newInstance(y, 1, 1).toStartOfMonth();
                lastDateOfMonth = !isSameYear
                    ? Date.newInstance(y, 12, Date.daysInMonth(y, 12))
                    : todaysDate;
            }

            dateMap.put('firstDateOfMonth', firstDateOfMonth.format());
            dateMap.put('lastDateOfMonth', lastDateOfMonth.format());
            return dateMap;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Returns the quarter number for a specified date
    public static Integer findQuarter(Date aDate) {
        Integer currentQuarter;
        if (aDate.month() / 3.0 <= 1) {
            currentQuarter = 1;
        } else if (aDate.month() / 3.0 <= 2) {
            currentQuarter = 2;
        } else if (aDate.month() / 3.0 <= 3) {
            currentQuarter = 3;
        } else {
            currentQuarter = 4;
        }
        return currentQuarter;
    }

    // Retrieves transaction fields for the advanced filter component
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getTranscationFields(Boolean isGodMode) {
        Map<String, TransactionField> transactionMetadataMap = new Map<String, TransactionField>();
        List<Map<String, String>> nodeMapList = new List<Map<String, String>>();

        if (!isGodMode) {
            TransactionViewer.jeFieldBlockList.add('uhn_fcc__c');
            TransactionViewer.jeFieldBlockList.add('uhn_fcc_sap_id__c');
        }

        for (String key : TransactionViewer.transactionFieldsMap.keySet()) {
            if (TransactionViewer.jeFieldBlockList.contains(key)) {
                continue;
            }
            TransactionField tf = new TransactionField(key);
            if (!jeTypeAllowList.contains(tf.type) || !tf.isAccessible) {
                continue;
            }
            transactionMetadataMap.put(key, tf);

            String name = transactionMetadataMap.get(key).name;
            String apiName = transactionMetadataMap.get(key).apiName;
            nodeMapList.add(new Map<String, String>{'label' => name, 'value' => apiName});
        }

        return new Map<String, Object>{
            'transactionFieldMetdataMap' => transactionMetadataMap,
            'nodeMapList' => nodeMapList
        };
    }

    public class TransactionItem {
        @AuraEnabled public String creationDate;
        @AuraEnabled public Integer dateOrdinal; // used for sorting dates
        @AuraEnabled public String name;
        @AuraEnabled public String fccNumber;
        @AuraEnabled public String fccLabel;
        @AuraEnabled public String fccID;
        @AuraEnabled public String fccURL;
        @AuraEnabled public Decimal availableAmount;
        @AuraEnabled public Decimal originalAmount;
        @AuraEnabled public String glTransactionType;
        @AuraEnabled public String glName;
        @AuraEnabled public String glDescription;
        @AuraEnabled public String costElementDescription;
        @AuraEnabled public String status;
        @AuraEnabled public String vendor;
        @AuraEnabled public String poNumber;
        @AuraEnabled public Boolean transactionUnavailable;
        @AuraEnabled public Id transactionID;

        public TransactionItem(UHN_Journal_Entry__c jounralEntry) {
            Date jeDate = jounralEntry.UHN_Calculated_Date_Key__c;
            creationDate = monthsMap.get(jeDate.month()) + ' ' + jeDate.day() + ', ' + jeDate.year();
            dateOrdinal = jounralEntry.UHN_Calculated_Date_Key__c.daysBetween(Date.today());
            name = jounralEntry.Name;

            fccNumber = jounralEntry.UHN_FCC__r.Name;
            if (jounralEntry.UHN_FCC__r.UHN_Name__c.startsWith(fccNumber)) {
                fccLabel = jounralEntry.UHN_FCC__r.UHN_Name__c;
            } else {
                fccLabel = fccNumber + ' - ' + jounralEntry.UHN_FCC__r.UHN_Name__c;
            }

            fccID = jounralEntry.UHN_FCC__c;

            String networkId = Network.getNetworkId();
            if (networkId != null) {
                fccURL = Site.getBaseSecureUrl() + '/uhn-fcc/' + fccID;
            } else {
                fccURL = URL.getOrgDomainUrl().toExternalForm() + '/' + fccID;
            }

            glTransactionType = jounralEntry.UHN_GL_Account__r.UHN_PI_Expense_or_Revenue_Type__c;
            glName = jounralEntry.UHN_GL_Account__r.Name;
            costElementDescription = jounralEntry.UHN_GL_Account__r.UHN_Cost_Element_Description__c;

            if (costElementDescription != null) {
                glDescription = glName + ' - ' + jounralEntry.UHN_GL_Account__r.UHN_Cost_Element_Description__c;
            } else {
                glDescription = glName;
            }

            status = jounralEntry.UHN_Transfer_Status__c;
            availableAmount = jounralEntry.UHN_Actual_Amount__c * -1;
            originalAmount = jounralEntry.UHN_Display_Amount__c;
            vendor = jounralEntry.UHN_Vendor_Name__c;
            poNumber = jounralEntry.UHN_Purchase_Order_Number__c;
            transactionUnavailable = (jounralEntry.UHN_Actual_Amount__c == 0);
            transactionID = jounralEntry.Id;
        }
    }

    // Used for advanced filter
    public class TransactionField {
        @AuraEnabled public String name;
        @AuraEnabled public String apiName;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean encloseWithQuotes;
        @AuraEnabled public Boolean isBoolean;

        public Boolean isAccessible;

        public TransactionField(String apiName) {
            Schema.DescribeFieldResult dfr = TransactionViewer.transactionFieldsMap.get(apiName).getDescribe();
            name = dfr.getLabel();
            this.apiName = apiName;
            type = dfr.getType().toString();
            isAccessible = dfr.isAccessible();

            switch on (dfr.getType()) {
                when CURRENCY, LONG, DOUBLE, INTEGER, DATE {
                    encloseWithQuotes = false;
                }
                when else {
                    encloseWithQuotes = true;
                }
            }

            isBoolean = (Schema.DisplayType.BOOLEAN == dfr.getType());
        }
    }
}