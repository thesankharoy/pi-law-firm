public with sharing class IntakeDashboardController {

 // ---- public methods (called by the LWC) ----

    @AuraEnabled(cacheable=true)
    public static Integer getTotalLeadsEntered(String dateFilter, Date startDate, Date endDate) {
        return countIntakes(null, dateFilter, startDate, endDate);
    }

    @AuraEnabled(cacheable=true)
    public static Integer getSignedClients(String dateFilter, Date startDate, Date endDate) {
        return countIntakes('Status__c = \'Retainer Agreement Signed\'', dateFilter, startDate, endDate);
    }

    @AuraEnabled(cacheable=true)
    public static Decimal getConversionRate(String dateFilter, Date startDate, Date endDate) {
        Integer total     = countIntakes(null, dateFilter, startDate, endDate);
        Integer converted = countIntakes('Status__c = \'Converted\'', dateFilter, startDate, endDate);
        if (total == 0) return 0;
        return (((Decimal) converted / total) * 100).setScale(2, System.RoundingMode.HALF_UP);
    }
    
    @AuraEnabled(cacheable=true)
    public static Decimal getOverallConversionRate() {
    Integer total = countIntakes(null, null, null, null);
    Integer converted = countIntakes('Status__c = \'Converted\'', null, null, null);

    if (total == 0) {
        return 0;
    }

    return (((Decimal) converted / total) * 100)
        .setScale(2, System.RoundingMode.HALF_UP);
  }

    // ---- shared counting helper ----

    private static Integer countIntakes(String extraFilter, String dateFilter, Date startDate, Date endDate) {

        List<String> conds = new List<String>();
        if (String.isNotBlank(extraFilter)) {
            conds.add(extraFilter);
        }

        // Custom range takes priority when supplied
        Datetime startDt;
        Datetime endDt;
        if (dateFilter == 'CUSTOM' && startDate != null && endDate != null) {
            startDt = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            endDt   = Datetime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0)); // inclusive end day
            conds.add('CreatedDate >= :startDt');
            conds.add('CreatedDate < :endDt');
        } else {
            String lit = dateLiteral(dateFilter);
            if (lit != null) {
                conds.add('CreatedDate = ' + lit); // safe: value validated against allow-list
            }
        }

        String q = 'SELECT COUNT() FROM Intake__c';
        if (!conds.isEmpty()) {
            q += ' WHERE ' + String.join(conds, ' AND ');
        }
        return Database.countQuery(q);
    }

    // whitelist of SOQL date literals -> prevents injection, ignores anything unknown/ALL
    private static String dateLiteral(String f) {
        Set<String> allowed = new Set<String>{
            'TODAY','YESTERDAY','THIS_WEEK','LAST_WEEK','THIS_MONTH','LAST_MONTH',
            'THIS_QUARTER','LAST_QUARTER','THIS_YEAR','LAST_YEAR'
        };
        return allowed.contains(f) ? f : null;
    }

    
    
   @AuraEnabled(cacheable=true)
    public static List<ResponseTimeWrapper> getResponseTimeData() {
        List<ResponseTimeWrapper> results = new List<ResponseTimeWrapper>();
        Decimal maxTime = 0;

        List<AggregateResult> queryResults = [
            SELECT Source__c source, AVG(Business_Response_Minutes__c) avgTime
            FROM Intake__c
            WHERE Business_Response_Minutes__c != NULL
            AND Business_Response_Minutes__c >= 0
            GROUP BY Source__c
        ];

        for (AggregateResult ar : queryResults) {
            Decimal avgTime = (Decimal) ar.get('avgTime');
            if (avgTime != null && avgTime > maxTime) maxTime = avgTime;
        }

        for (AggregateResult ar : queryResults) {
            ResponseTimeWrapper row = new ResponseTimeWrapper();
            row.source = (String) ar.get('source');
            Decimal avgTime = (Decimal) ar.get('avgTime');
            row.avgResponseTime = (avgTime == null || avgTime < 0) ? 0 : avgTime;
            row.percentage = maxTime > 0
                ? ((maxTime - row.avgResponseTime) / maxTime) * 100
                : 100;
            results.add(row);
        }

        results.sort(new ResponseTimeSorter());
        return results;
    }

    // ---------- FLOW: business-hours response minutes ----------
    @InvocableMethod(label='Business-Hours Response Minutes')
    public static List<MinutesResult> computeBusinessMinutes(List<MinutesRequest> reqs) {
        List<MinutesResult> out = new List<MinutesResult>();
        BusinessHours bh = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];

        for (MinutesRequest r : reqs) {
            MinutesResult res = new MinutesResult();
            if (r.createdDt != null && r.firstResponseDt != null
                && r.firstResponseDt >= r.createdDt) {
                Long ms = BusinessHours.diff(bh.Id, r.createdDt, r.firstResponseDt);
                res.minutes = ms / 60000.0;   // milliseconds -> minutes
            } else {
                res.minutes = null;
            }
            out.add(res);
        }
        return out;
    }

    // ---------- wrappers ----------
    public class MinutesRequest {
        @InvocableVariable public Datetime createdDt;
        @InvocableVariable public Datetime firstResponseDt;
    }
    public class MinutesResult {
        @InvocableVariable public Decimal minutes;
    }

    public class ResponseTimeWrapper {
        @AuraEnabled public String source;
        @AuraEnabled public Decimal avgResponseTime;
        @AuraEnabled public Decimal percentage;
    }

    public class ResponseTimeSorter implements Comparator<ResponseTimeWrapper> {
        public Integer compare(ResponseTimeWrapper a, ResponseTimeWrapper b) {
            if (a.avgResponseTime > b.avgResponseTime) return 1;
            if (a.avgResponseTime < b.avgResponseTime) return -1;
            return 0;
        }
    }

}