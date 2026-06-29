public with sharing class AISentimentDashboardController {
    
    private static final Integer PAGE_SIZE = 7;
    
    //===========================
    // Wrapper Classes
    //===========================
    
    public class DashboardResponse {
        
        @AuraEnabled
        public Integer totalIntakes;
        
        @AuraEnabled
        public Integer totalCalls;
        
        @AuraEnabled
        public String averageSentiment;
        
        @AuraEnabled
        public Integer totalRecords;
        
        @AuraEnabled
        public Integer currentPage;
        
        @AuraEnabled
        public Integer pageSize;
        
        @AuraEnabled
        public List<IntakeRow> records;
    }
    
    public class IntakeRow {
        
        @AuraEnabled
        public Id intakeId;
        
        @AuraEnabled
        public String intakeName;
        
        @AuraEnabled
        public String sentiment;
        
        @AuraEnabled
        public Integer callCount;
        
        @AuraEnabled
        public DateTime lastCallDate;
        
    }
    
    @AuraEnabled(cacheable=true)
    public static DashboardResponse getDashboardData(
        String filterType,
        Integer pageNumber
    ){
        
        if(pageNumber == null || pageNumber <= 0){
            pageNumber = 1;
        }
        
        DashboardResponse response = new DashboardResponse();
        
        response.pageSize = PAGE_SIZE;
        response.currentPage = pageNumber;
        response.records = new List<IntakeRow>();
        
        Date startDate;
        Date endDate;
        Boolean isAll = false;
        
        switch on filterType {
            
            when 'All' {
                
                isAll = true;
                
            }
            
            when 'Today' {
                
                startDate = Date.today();
                endDate = Date.today();
                
            }
            
            when 'Yesterday' {
                
                startDate = Date.today().addDays(-1);
                endDate = Date.today().addDays(-1);
                
            }
            
            when 'This Month' {
                
                startDate = Date.newInstance(
                    Date.today().year(),
                    Date.today().month(),
                    1
                );
                
                endDate = startDate.addMonths(1).addDays(-1);
                
            }
            
            when 'Last Month' {
                
                Date lastMonth = Date.today().addMonths(-1);
                
                startDate = Date.newInstance(
                    lastMonth.year(),
                    lastMonth.month(),
                    1
                );
                
                endDate = startDate.addMonths(1).addDays(-1);
                
            }
            
            when else {
                
                isAll = true;
                
            }
            
        }
        
        Integer offsetRows =
            (pageNumber - 1) * PAGE_SIZE;
        
        //=========================================
        // Total Intake Records
        //=========================================
        
        if (isAll) {
            
            response.totalRecords = [
                SELECT COUNT()
                FROM Intake__c
            ];
            
        } else {
            
            response.totalRecords = [
                SELECT COUNT()
                FROM Intake__c
                WHERE CreatedDate >= :startDate
                AND CreatedDate < :endDate.addDays(1)
            ];
            
        }
        
        //=========================================
        // Get Intake Records
        //=========================================
        
        List<Intake__c> intakeList;
        
        if (isAll) {
            
            intakeList = [
                SELECT Id,
                Name,
                AI_Sentiment__c,
                CreatedDate
                FROM Intake__c
                ORDER BY CreatedDate DESC
                LIMIT :PAGE_SIZE
                OFFSET :offsetRows
            ];
            
        } else {
            
            intakeList = [
                SELECT Id,
                Name,
                AI_Sentiment__c,
                CreatedDate
                FROM Intake__c
                WHERE CreatedDate >= :startDate
                AND CreatedDate < :endDate.addDays(1)
                ORDER BY CreatedDate DESC
                LIMIT :PAGE_SIZE
                OFFSET :offsetRows
            ];
            
        }
        
        response.totalIntakes = response.totalRecords;
        
        if(intakeList.isEmpty()){
            
            response.totalCalls = 0;
            response.averageSentiment = 'No Data';
            
            return response;
        }
        
        //=========================================
        // Collect Intake Ids
        //=========================================
        
        Set<Id> intakeIds = new Set<Id>();
        
        Integer sentimentScore = 0;
        
        for(Intake__c intake : intakeList){
            
            intakeIds.add(intake.Id);
            
            if(intake.AI_Sentiment__c == 'Positive'){
                
                sentimentScore += 3;
                
            }else if(intake.AI_Sentiment__c == 'Neutral'){
                
                sentimentScore += 2;
                
            }else if(intake.AI_Sentiment__c == 'Negative'){
                
                sentimentScore += 1;
            }
        }
        
        Decimal averageScore =
            Decimal.valueOf(sentimentScore) /
            intakeList.size();
        
        if(averageScore >= 2.5){
            
            response.averageSentiment = 'Positive';
            
        }else if(averageScore >= 1.5){
            
            response.averageSentiment = 'Neutral';
            
        }else{
            
            response.averageSentiment = 'Negative';
        }
        
        //=========================================
        // Aggregate Task Data
        //=========================================
        
        Map<Id,Integer> callCountMap =
            new Map<Id,Integer>();
        
        Map<Id,DateTime> lastCallMap =
            new Map<Id,DateTime>();
        
        for(AggregateResult ar : [
            
            SELECT
            WhatId intakeId,
            COUNT(Id) totalCalls,
            MAX(CreatedDate) lastCall
            FROM Task
            WHERE WhatId IN :intakeIds
            AND Status = 'Completed'
            AND (
                Subject LIKE 'Inbound Call%'
                OR Subject LIKE 'Outbound Call%'
            )
            GROUP BY WhatId
            
        ]){
            
            Id intakeId =
                (Id)ar.get('intakeId');
            
            callCountMap.put(
                intakeId,
                (Integer)ar.get('totalCalls')
            );
            
            DateTime lastDateTime = (DateTime) ar.get('lastCall');
            
            if (lastDateTime != null) {
                lastCallMap.put(intakeId, lastDateTime);
            }
        }
        
        Integer totalCalls = 0;
        //=========================================
        // Build Dashboard Rows
        //=========================================
        
        for (Intake__c intake : intakeList) {
            
            IntakeRow row = new IntakeRow();
            
            row.intakeId = intake.Id;
            row.intakeName = intake.Name;
            row.sentiment = intake.AI_Sentiment__c;
            
            if (callCountMap.containsKey(intake.Id)) {
                row.callCount = callCountMap.get(intake.Id);
                totalCalls += row.callCount;
            } else {
                row.callCount = 0;
            }
            
            if (lastCallMap.containsKey(intake.Id)) {
                row.lastCallDate = lastCallMap.get(intake.Id);
            }
            
            response.records.add(row);
        }
        
        response.totalCalls = totalCalls;
        
        return response;
    }
    
}