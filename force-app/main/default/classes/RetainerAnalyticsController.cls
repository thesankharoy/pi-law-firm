public with sharing class RetainerAnalyticsController {

    public class RetainerAnalyticsDTO {
        @AuraEnabled public Integer sentCount;
        @AuraEnabled public Integer openCount;
        @AuraEnabled public Integer signedCount;
        @AuraEnabled public Decimal conversionRate;
        @AuraEnabled public Decimal avgDaysToSign;
    }

   @AuraEnabled(cacheable=true)
public static RetainerAnalyticsDTO getAnalytics(String filterType) {

    RetainerAnalyticsDTO dto = new RetainerAnalyticsDTO();

    String dateFilter = '';

    switch on filterType {

        when 'TODAY' {
            dateFilter = ' CreatedDate = TODAY';
        }
        when 'YESTERDAY' {
            dateFilter = ' CreatedDate = YESTERDAY';
        }
        when 'LAST_7_DAYS' {
            dateFilter = ' CreatedDate = LAST_N_DAYS:7';
        }
        when 'THIS_MONTH' {
            dateFilter = ' CreatedDate = THIS_MONTH';
        }
        when 'LAST_MONTH' {
            dateFilter = ' CreatedDate = LAST_MONTH';
        }
        when 'THIS_YEAR' {
            dateFilter = ' CreatedDate = THIS_YEAR';
        }
        when else {
            dateFilter = '';
        }
    }

    String whereClause =
        (dateFilter == '')
        ? ''
        : ' AND ' + dateFilter;

    // Sent
    dto.sentCount = Database.countQuery(
        'SELECT COUNT() FROM Intake__c ' +
        'WHERE Status__c = \'Retainer Agreement Sent\'' +
        whereClause
    );

    // Viewed
    dto.openCount = Database.countQuery(
        'SELECT COUNT() FROM Intake__c ' +
        'WHERE Status__c = \'Assigned\'' +
        whereClause
    );

    // Signed
    dto.signedCount = Database.countQuery(
        'SELECT COUNT() FROM Intake__c ' +
        'WHERE Status__c = \'Retainer Agreement Signed\'' +
        whereClause
    );

    // Conversion Rate
    dto.conversionRate =
        dto.sentCount > 0
        ? (Decimal.valueOf(dto.signedCount) / Decimal.valueOf(dto.sentCount)) * 100
        : 0;

    // Average Days to Sign
    String query =
        'SELECT Retainer_Agreement_Sent_Entered_At__c,' +
        ' Retainer_Agreement_Signed_Entered_At__c ' +
        'FROM Intake__c ' +
        'WHERE Status__c = \'Retainer Agreement Signed\'' +
        ' AND Retainer_Agreement_Sent_Entered_At__c != null' +
        ' AND Retainer_Agreement_Signed_Entered_At__c != null' +
        whereClause;

    List<Intake__c> signedIntakes = Database.query(query);

    Decimal totalDays = 0;

    for (Intake__c i : signedIntakes) {

        Long diffMs =
            i.Retainer_Agreement_Signed_Entered_At__c.getTime() -
            i.Retainer_Agreement_Sent_Entered_At__c.getTime();

        totalDays += diffMs / (1000 * 60 * 60 * 24);
    }

    dto.avgDaysToSign =
        signedIntakes.isEmpty()
        ? 0
        : totalDays / signedIntakes.size();

    return dto;
}
}