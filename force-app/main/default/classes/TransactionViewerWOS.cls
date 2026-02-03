public without sharing class TransactionViewerWOS {
	
	static User contextUser = [SELECT ID, ContactId FROM User WHERE id =: UserInfo.getUserId()];
	static final String EMAIL_TEMPLATE_NAME = 'Expense_Transfer_Approval_Request_to_Approver_2';
	static EmailTemplate emailTemplate = [SELECT Id,Subject, Body FROM EmailTemplate WHERE developerName =: EMAIL_TEMPLATE_NAME];
	public class QueryCharacterLimitException extends Exception {}
	public class OutdatedTransactionException extends Exception {}

	public static List<UHN_Journal_Entry__c> getTransactions(Set<ID> journalEntryIDs) {
		List<UHN_Journal_Entry__c> journalEntriesWOS = [SELECT name, UHN_Calculated_Date_Key__c, UHN_Actual_Amount__c, UHN_FCC__r.name, UHN_FCC__r.UHN_Name__c, UHN_GL_Account__r.UHN_Cost_Element_Description__c, UHN_GL_Account__r.name,
															UHN_GL_Account__r.UHN_PI_Expense_or_Revenue_Type__c, UHN_GL_Account__r.UHN_GL_Account_Description__c, UHN_Transfer_Status__c, 
															UHN_Display_Amount__c, UHN_Absolute_Transferable_Amount__c, UHN_Vendor_Name__c, UHN_Purchase_Order_Number__c, UHN_Debit_or_Credit__c, id                                                 
														FROM UHN_Journal_Entry__c 
														WHERE ID IN :journalEntryIDs ORDER BY UHN_Calculated_Date_Key__c ASC];
												
		return journalEntriesWOS;
	}

	public static List<UHN_Journal_Entry__c> getTransactionsRD(Set<ID> journalEntryIDs) {
		List<UHN_Journal_Entry__c> journalEntriesWOS = [SELECT name, UHN_Calculated_Date_Key__c, UHN_Actual_Amount__c, UHN_FCC__r.name, UHN_FCC__r.UHN_Name__c, UHN_GL_Account__r.UHN_Cost_Element_Description__c, UHN_GL_Account__r.name,
										UHN_GL_Account__r.UHN_PI_Expense_or_Revenue_Type__c, UHN_GL_Account__r.UHN_GL_Account_Description__c, UHN_Transfer_Status__c, 
										UHN_Display_Amount__c, UHN_Absolute_Transferable_Amount__c, UHN_Vendor_Name__c, UHN_Purchase_Order_Number__c, id                                                 
									FROM UHN_Journal_Entry__c 
									WHERE ID IN :journalEntryIDs
									ORDER BY UHN_Calculated_Date_Key__c ASC
								];
		return journalEntriesWOS;
	}

	
	// Retrieves a collection of transaction Ids with filters applied
	@AuraEnabled(cacheable=true)
	public static List<sObject> getFilteredTransactions(String filterClause, String searchPool){
		try {
			if (filterClause.length() > 18000)  {
				throw new QueryCharacterLimitException('Query character limit exceeded. Please reduce the amount of filters.');
			}
			Set<Id> transactionIDs = (Set<Id>)JSON.deserialize(searchPool, Set<Id>.class);
			String query = 'SELECT Id FROM UHN_Journal_Entry__c WHERE Id =: transactionIDs' + filterClause + ' ORDER BY UHN_Calculated_Date_Key__c ASC';
			return Database.query(query); 
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	// Used to return typeahead search results based on transaction name
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> searchTransactions(String textInput, String searchPool){
		try {
			Set<Id> transactionIDs = (Set<Id>)JSON.deserialize(searchPool, Set<Id>.class);
			String regEx = '%' + textInput + '%';
			List<Map<String, Object>> mapList = new List<Map<String, Object>>();
			List<UHN_Journal_Entry__c > journalEntries = [SELECT name, UHN_Actual_Amount__c, id  
														FROM UHN_Journal_Entry__c  WHERE name LIKE :regEx AND ID IN :transactionIDs 
														ORDER BY name ASC LIMIT 5];

			for (UHN_Journal_Entry__c je : journalEntries) {
				String textEntity = je.name;
				String textEntityHTML = TransactionViewer.highlightMatchedText(textEntity, textInput);
				String textMeta = 'Amount $' + je.UHN_Actual_Amount__c * - 1;
				// isGodMode: FCC Number ' + je.UHN_FCC__r.Name + '• Amount $' + je.UHN_Actual_Amount__c;
				mapList.add(new Map<String, Object> { 'textEntity' => textEntity, 'textEntityHTML' => textEntityHTML, 'textMeta' => textMeta, 'textMetaHTML' => null, 'id' => je.id});
			}											
			return mapList;
		} catch (Exception e) {
		throw new AuraHandledException(e.getMessage());
		}
	}

	// Used to return typeahaed search results for a GL Account based on the GL description
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> searchGLByAccount(String textInput, String searchPool){
		try {
			Set<Id> glIDs = (Set<Id>)JSON.deserialize(searchPool, Set<Id>.class);
			String regEx = '%' + textInput + '%';
			List<Map<String, Object>> mapList = new List<Map<String, Object>>();
			List<UHN_GL_Account__c > glAcc = [SELECT name, UHN_Cost_Element_Description__c, id  
														FROM UHN_GL_Account__c
														WHERE UHN_Cost_Element_Description__c LIKE :regEx AND ID IN :glIDs 
														ORDER BY UHN_Cost_Element_Description__c ASC LIMIT 5];			
			for (UHN_GL_Account__c gl : glAcc) {
				String textEntity = gl.UHN_Cost_Element_Description__c;
				String textMeta = gl.name;  
				String textEntityHTML = TransactionViewer.highlightMatchedText(textEntity, textInput);		
				mapList.add(new Map<String, Object> { 'textEntity' => textEntity, 'textEntityHTML' => textEntityHTML, 'textMeta' => textMeta, 'textMetaHTML' => null, 'id' => gl.id});

			}	
			return mapList;	
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	// Used to return typeahaed search results for a GL Account based on the GL name. The GL name is a number.
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> searchGLByID(String textInput, String searchPool){
		try {
			Set<Id> glIDs = (Set<Id>)JSON.deserialize(searchPool, Set<Id>.class);
			String regEx = '%' + textInput + '%';
			List<Map<String, Object>> mapList = new List<Map<String, Object>>();
			List<UHN_GL_Account__c > glAcc = [SELECT name, UHN_Cost_Element_Description__c, id  
														FROM UHN_GL_Account__c
														WHERE name LIKE :regEx AND ID IN :glIDs 
														ORDER BY name ASC LIMIT 5];

			for (UHN_GL_Account__c gl : glAcc) {
				String textEntity = gl.UHN_Cost_Element_Description__c;
				String textMeta = gl.name;
				String textMetaHTML = TransactionViewer.highlightMatchedText(textMeta, textInput);
				mapList.add(new Map<String, Object> { 'textEntity' => textEntity, 'textEntityHTML' => null, 'textMeta' => textMeta, 'textMetaHTML' => textMetaHTML, 'id' => gl.id});
			}											
			return mapList;
		} catch (Exception e) {
		throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * @param fccBlackList - contains atleast one value since the from FCC is always black listed
	 */
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> searchTargetFCCsByNumber(String textInput, String fccBlackList){
		try {
			List<Map<String, Object>> mapList = new List<Map<String, Object>>();
			String regEx = '%' + textInput + '%';
			List<UHN_FCC__c > fccRes;
	
			Set<Id> fccIDs = (Set<Id>)JSON.deserialize(fccBlackList, Set<Id>.class);
			fccRes =  [SELECT name, UHN_Name__c, id  
						FROM  UHN_FCC__c  WHERE name LIKE :regEx AND
						UHN_FCC_Status__c = 'Open' AND UHN_FCC_Type_long__c = 'Grant Internal Order' AND 
						UHN_NonSalary_Actuals_Allowed__c = 'Yes'  
						AND ID NOT IN :fccIDs  
						ORDER BY name ASC LIMIT 3];
			
			for (UHN_FCC__c fcc : fccRes) {
				String textEntity = fcc.name;
				String textEntityHTML = TransactionViewer.highlightMatchedText(textEntity, textInput);
				String textMeta = fcc.UHN_Name__c;
				String fccURL;
				String networkId = Network.getNetworkId();
				if ( networkId != null ) {  // Check if the context user is on a community page
					fccURL = Site.getBaseSecureUrl() + '/uhn-fcc/' + fcc.id;
				} else {
					fccURL = URL.getOrgDomainUrl().toExternalForm() + '/' + fcc.id;
				}
				mapList.add(new Map<String, Object> { 'textEntity' => textEntity, 'textEntityHTML' => textEntityHTML, 'textMeta' => textMeta, 'textMetaHTML' => null, 'id' => fcc.id, 'url' => fccURL});
			}			
			return mapList;	
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

		/**
	 * @param fccBlackList - contains atleast one value since the from FCC is always black listed
	 */
	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> searchTargetFCCsByDescription(String textInput, String fccBlackList){
		try {
			List<Map<String, Object>> mapList = new List<Map<String, Object>>();
			String regEx = '%' + textInput + '%';
			List<UHN_FCC__c > fccRes;
	
			Set<Id> fccIDs = (Set<Id>)JSON.deserialize(fccBlackList, Set<Id>.class);
			fccRes =  [SELECT name, UHN_Name__c, id  
						FROM  UHN_FCC__c  WHERE UHN_Name__c LIKE :regEx AND
						UHN_FCC_Status__c = 'Open' AND UHN_FCC_Type_long__c = 'Grant Internal Order' AND 
						UHN_NonSalary_Actuals_Allowed__c = 'Yes'  
						AND ID NOT IN :fccIDs  
						ORDER BY name ASC LIMIT 3];
			
			for (UHN_FCC__c fcc : fccRes) {
				String textEntity = fcc.name;
				String textMeta = fcc.UHN_Name__c;		
				String fccURL;
				String networkId = Network.getNetworkId();
				if ( networkId != null ) {  // Check if the context user is on a community page
					fccURL = Site.getBaseSecureUrl() + '/uhn-fcc/' + fcc.id;
				} else {
					fccURL = URL.getOrgDomainUrl().toExternalForm() + '/' + fcc.id;
				}
				String textMetaHTML = TransactionViewer.highlightMatchedText(textMeta, textInput);
				mapList.add(new Map<String, Object> { 'textEntity' => textEntity, 'textEntityHTML' => null, 'textMeta' => textMeta, 'textMetaHTML' => textMetaHTML, 'id' => fcc.id, 'url' => fccURL});
			}			
			return mapList;	
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	/**
	 * Create a valid approver
	 * 
	 * @param contactobj - a contact who can approve an ET
	 * @param isAutoApproval - determines if node will be an auto approval
	 * @param validApprovers - list of valid approvers
	 * returns - the created approver. Returns an empty node if the current user is the auto approver and a auto approver has already been determined
	 */
	public static Map<String, Object> createValidApproverNode(Contact contactObj, Boolean isAutoApproverDetermined, List<Map<String, Object>> validApprovers) {
			String value;
			Boolean isAutoApproval; 
			if (isAutoApproverDetermined && UserInfo.getUserId() == (String) contactObj.UHN_User__c) {
				return new Map<String, Object>{};
			}
			if (!isAutoApproverDetermined && UserInfo.getUserId() == (String) contactObj.UHN_User__c) {
				value = 'Auto Approve';
				isAutoApproval = true;
			} else {
				value = contactObj.UHN_Full_Name__c;
				isAutoApproval = false;
			}
			String networkId = Network.getNetworkId();
			String contactObjBaseURL;
			if ( networkId != null ) {  // Check if the context user is on a community page
				contactObjBaseURL = Site.getBaseSecureUrl() + '/contact';
			} else {
				contactObjBaseURL = URL.getOrgDomainUrl().toExternalForm();
			}
			String contactObjURL = contactObjBaseURL + '/' + contactObj.id;
			Map<String, Object> approverNode = new Map<String, Object> {'value' => value, 'url' =>  contactObjURL, 'isAutoApproval' => isAutoApproval, 'id' => contactObj.id, 'userID' => contactObj.UHN_User__c, 'contactID' => contactObj.id, 'contactEmail' => contactObj.Email};
			validApprovers.add(approverNode);
			return approverNode;
	}

	/**
	 * A valid approver must have their UHN_User__c field populated
	 * Reuturns a map object containing
	 *    1. a valid approver node containing all valid approvers
	 *    2. the autoApprover node which is needed to easibly identify the auto approver when prefilling daata
	*/
	@AuraEnabled(cacheable=true)
	public static Map<String, Object> getTargetFCC_Approvers(String toFCC_ID, Decimal transferAmount) {
		try {
			ID fccID =  ID.valueOf(toFCC_ID);
			// Map<String, List<Map<String, Object>>>
			Map<String, Object> autoApprover = new Map<String, Object>();
			List<Map<String, Object>> validApprovers = new List<Map<String, Object>>();
			Boolean isAutoApproverDetermined = false;

			List<UHN_FCC__c> fccList = [SELECT UHN_Contact__c, UHN_Financial_Analyst_1__c FROM UHN_FCC__c WHERE id =: fccID LIMIT 1];
			UHN_FCC__c fcc = fccList.get(0);

			List<Contact> accountHolderList = [SELECT UHN_Full_Name__c, UHN_User__c, Email, id FROM Contact WHERE id =: fcc.UHN_Contact__c AND UHN_User__c != null AND UHN_Active_User__c = true LIMIT 1];
			List<Contact> faList = [SELECT UHN_Full_Name__c, UHN_User__c, Email, id FROM Contact WHERE id =: fcc.UHN_Financial_Analyst_1__c  AND UHN_User__c != null AND UHN_Active_User__c = true LIMIT 1];
			List<UHN_Delegate__c> delegateList = [SELECT UHN_Contact__r.UHN_Full_Name__c, UHN_Contact__r.UHN_User__c,  UHN_Contact__r.Email FROM UHN_Delegate__c 
												WHERE UHN_FCC__c =: fccID AND (UHN_Signing_Limit__c >= :transferAmount OR UHN_Has_Unlimited_Signing__c = true)
													AND UHN_Active_User__c = true AND UHN_Active_Record__c = true AND UHN_Contact__r.UHN_User__c != null 
													AND UHN_Contact__r.UHN_Active_User__c = true AND UHN_Signing_Authority_Status__c = 'Active' 
												];												
			List<Id> delegateIds = new List<Id>();
			for (UHN_Delegate__c dl : delegateList) {
           		 delegateIds.add(dl.UHN_Contact__c);
      	    }
			List<Contact> delegateContactList = [SELECT UHN_Full_Name__c, UHN_User__c, Email, id FROM Contact WHERE id IN :delegateIds];

			// FA can only be a valid approver if he is the context user
			if (!faList.isEmpty() && UserInfo.getUserId() == (String) faList.get(0).UHN_User__c) {
				Contact fa = faList.get(0);
				Map<String, Object> approverNode = createValidApproverNode(fa, isAutoApproverDetermined, validApprovers);
				if ((Boolean) approverNode.get('isAutoApproval') == true) {
					if (approverNode.size() != 0) {
						autoApprover = approverNode;
					}
					isAutoApproverDetermined = true;
				}
			}

			if (!accountHolderList.isEmpty()) {
		    	Contact accountHolder = accountHolderList.get(0);
				Map<String, Object> approverNode = createValidApproverNode(accountHolder, isAutoApproverDetermined, validApprovers);
				if ((Boolean) approverNode.get('isAutoApproval') == true) {
					if (approverNode.size() != 0) {
						autoApprover = approverNode;
					}
					isAutoApproverDetermined = true;
				}
			}

			for (Contact delegate : delegateContactList) {
				Map<String, Object> approverNode = createValidApproverNode(delegate, isAutoApproverDetermined, validApprovers);
				if ((Boolean) approverNode.get('isAutoApproval') == true) {
					if (approverNode.size() != 0) {
						autoApprover = approverNode;
					}
					isAutoApproverDetermined = true;
				}
			}
			return new Map<String, Object> {'validApprovers' => validApprovers, 'autoApprover' => autoApprover};
		} catch(Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<Map<String, Object>> caseRationalsET() {
		try {
			List<Map<String, Object>> rationalsMapList = new List<Map<String, Object>>();
			Map<String, Object> rationalsMap = new Map<String, Object>();
			List<Schema.PicklistEntry> pe = Schema.sObjectType.Case.fields.UHN_ET_Request_Rationale__c.getPicklistValues();
			for (Integer i = 0; i < pe.size() ; i++) {
				rationalsMapList.add(new Map<String, Object> {'id' => i, 'value' => pe.get(i).getValue()} );
			}
			return rationalsMapList;
		} catch (Exception e) {
	    	throw new AuraHandledException(e.getMessage());
		}
	}

   /*
	* Do not modify the orignal transaction. This is used for cloning purposes only. Changes to the transferable amount field are
	* calculated by a rollup summary
	*/
	@AuraEnabled(cacheable=false)
	public static List<URL_Node> createNonSalaryET(String etNodesJSON) {
		try {
			List<Case> casesToCreate = new List<Case>();
			ID caseRecordType = SObjectType.Case.getRecordTypeInfosByDeveloperName().get('Transfer_Request').getRecordTypeId();

			List<ET_Node> etNodes = (List<ET_Node>)JSON.deserialize(etNodesJSON, List<ET_Node>.class);
			List<Case> casesToInsert = new List<Case>();
			List<UHN_Journal_Entry__c> splitsToInsert =  new List<UHN_Journal_Entry__c>();
			Map<String, Case> etCaseIdToCreatedCase = new Map<String, Case>();
			List<UHN_Transfer_Journal_Entry__c> transferJEsToInsert = new List<UHN_Transfer_Journal_Entry__c>();

			// Create Case records from the Expense transfer to-from pair
			for (ET_Node etNode : etNodes) {
				Case newCase = new Case (subject = etNode.name, 
			                        	UHN_Total_Requested_Amount__c =  etNode.totalTransfer,
										UHN_Total_Transfer_Amount__c = etNode.totalTransfer,
										UHN_From_FCC__c = etNode.fromFCC_ID,
										UHN_To_FCC__c = etNode.toFCC_ID,
										UHN_Approver_2__c = etNode.daUserID, 
										UHN_ET_Request_Rationale__c = etNode.rational,
										RecordTypeId = caseRecordType,
										ContactId = etNode.daContactID,
										Origin = 'Lightning_Component',
										OwnerId = etNode.daUserID
										);				
				newCase.status = etNode.isAutoApproval ? 'In Progress' : 'Awaiting Approvals';
				casesToInsert.add(newCase);
				// Collect a map of case IDs to transactions so that the transfer transaction obj can be created easily
				etCaseIdToCreatedCase.put(etNode.id, newCase);
			}
			insert casesToInsert;

			List<URL_Node> caseURL_Nodes = new List<URL_Node>();

			String networkId = Network.getNetworkId();
			String caseBaseUrl;
			if ( networkId != null ) {  // Check if the context user is on a community page
				caseBaseUrl = Site.getBaseSecureUrl() + '/case';
			} else {
				caseBaseUrl = URL.getOrgDomainUrl().toExternalForm();
			}

            for ( Case item: casesToInsert) {
                caseURL_Nodes.add(new URL_Node( caseBaseUrl + '/' + item.id,  item.Subject));
            }
			// Transactions splits can result in duplicate journal entry Ids
			Set<Id> journalEntryIdSet = new Set<Id>();
			for (ET_Node etNode : etNodes) {
				for (ET_Node.TransactionNode expenseNode : etNode.transactions) {
                    String uniqueId = DateTime.now().format('yyyy-MM-dd-HH-mm-ss-SSS') + UUID.randomUUID().toString();                        
					UHN_Transfer_Journal_Entry__c transferJE_Credit = new UHN_Transfer_Journal_Entry__c (
						UHN_Inverse__c = false, // Credit Transaction
						UHN_Requested_Amount__c = expenseNode.transferAmount * -1,
						UHN_Amount__c = expenseNode.transferAmount  * -1,
						UHN_Journal_Entry__c = expenseNode.transactionID,
						UHN_Transfer_Request__c	= etCaseIdToCreatedCase.get(etNode.Id).id,
						UHN_Transfer_Transaction_Pair_ID__c = uniqueId		
					);
					UHN_Transfer_Journal_Entry__c transferJE_Debit = new UHN_Transfer_Journal_Entry__c (
						UHN_Inverse__c = true, // Debit Transasction
						UHN_Requested_Amount__c = expenseNode.transferAmount,
						UHN_Amount__c = expenseNode.transferAmount,
						UHN_Journal_Entry__c = expenseNode.transactionID,
						UHN_Transfer_Request__c	= etCaseIdToCreatedCase.get(etNode.Id).id,
						UHN_Transfer_Transaction_Pair_ID__c = uniqueId
					);
					transferJEsToInsert.add(transferJE_Credit);
					transferJEsToInsert.add(transferJE_Debit);
					journalEntryIdSet.add(expenseNode.transactionID);
				}
			}
			insert transferJEsToInsert;
			// update 
			// Case in which a user modifies an outdated transaction and the transfer amount results in value greater than the transferrable amount. This happens when the value is a positive number
			List<UHN_Journal_Entry__c>  journalEntries = [SELECT name FROM UHN_Journal_Entry__c WHERE ID IN:journalEntryIdSet AND UHN_Actual_Amount__c > 0];
			if (!journalEntries.isEmpty()) {
				String invalidTransactions = '';
				for (UHN_Journal_Entry__c je : journalEntries) {
					invalidTransactions += '<strong>' + je.name + ' ( ' + je.id + ' )' + '</strong>, ';
				}
				invalidTransactions = invalidTransactions.substring(0, invalidTransactions.length() - 2);
				throw new OutdatedTransactionException('The following transactions have outdated transferrable amounts: ' + invalidTransactions + '. Please refresh the component to have updated information.');
			}

			// Submit case for approval. Cases that are not auto approved are handled by a flow trigger
			for (ET_Node etNode : etNodes) {
					Case newCase = etCaseIdToCreatedCase.get(etNode.id);
					Approval.ProcessSubmitRequest processReq = new Approval.ProcessSubmitRequest();
					processReq.setObjectId(newCase.id);
					processReq.setSubmitterId(contextUser.id);
					processReq.setProcessDefinitionNameOrId('UHN_Transfer_Transaction_Approval_GS');
				if (etNode.isAutoApproval) {
					// Auto approve request 
					processReq.setSkipEntryCriteria(true);
					Approval.ProcessResult result = Approval.process(processReq);
					// Get ID of newly created work item
					List<Id> newWorkItemIds = result.getNewWorkitemIds();
					Approval.ProcessWorkitemRequest approvReq = new Approval.ProcessWorkitemRequest();
					approvReq.setComments('Auto approved by initiator.');
					approvReq.setAction('Approve');
					approvReq.setWorkitemId(newWorkItemIds.get(0));
					Approval.ProcessResult result2 =  Approval.process(approvReq);
				} else { 
					Approval.ProcessResult result = Approval.process(processReq);
				}	
			}
			return caseURL_Nodes;	      
		} catch (Exception e) {
			String errorMsg = e.getTypeName() + ': ' +  e.getMessage();
            AuraHandledException ahe = new AuraHandledException(errorMsg);
            ahe.setMessage(errorMsg);
			throw ahe;
		}
	}

	public class URL_Node {
        @AuraEnabled public String url; 
        @AuraEnabled public String content; 

        public URL_Node(String url, String content) {
            this.url = url;
            this.content = content;
        }
	}
}