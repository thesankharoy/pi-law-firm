public with sharing class ToolExecutor {

    private static final Integer MAX_ROWS = 200;
    // Sensitive PII fields blocked from the generic query tool (direct-API egress)
    private static final String BLOCKED_FIELDS_RE = '(?i)(\\bSSN__c\\b|\\bBirthdate\\b|\\bDate_of_Birth__c\\b)';

    public static String run(String name, Map<String, Object> input) {
        if (input == null) input = new Map<String, Object>();
        try {
            switch on name {
                when 'list_objects'        { return listObjects(input); }
                when 'describe_object'     { return describeObject(input); }
                when 'soql_query'          { return soqlQuery(input); }
                when 'run_report'          { return runReport(input); }
                when 'faq_lookup'          { return faqLookup(input); }
                when 'conversion_forecast' { return conversionForecast(input); }
                when 'source_quality'      { return sourceQuality(input); }
                when else                  { return 'Unknown tool: ' + name; }
            }
        } catch (Exception e) {
            return 'Tool error in ' + name + ': ' + e.getMessage();
        }
    }

    private static String listObjects(Map<String, Object> input) {
        String filter = (String) input.get('filter');
        filter = filter == null ? '' : filter.toLowerCase();
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (String key : Schema.getGlobalDescribe().keySet()) {
            Schema.DescribeSObjectResult d = Schema.getGlobalDescribe().get(key).getDescribe();
            if (!d.isQueryable() || !d.isAccessible()) continue;
            String api = d.getName();
            String label = d.getLabel();
            if (filter != '' && !api.toLowerCase().contains(filter) && !label.toLowerCase().contains(filter)) continue;
            out.add(new Map<String, Object>{ 'api' => api, 'label' => label });
            if (out.size() >= 200) break;
        }
        return JSON.serialize(new Map<String, Object>{ 'count' => out.size(), 'objects' => out });
    }

    private static String describeObject(Map<String, Object> input) {
        String name = (String) input.get('objectApiName');
        if (String.isBlank(name)) return 'objectApiName is required.';
        Schema.SObjectType t = Schema.getGlobalDescribe().get(name);
        if (t == null) return 'Unknown object: ' + name;
        Schema.DescribeSObjectResult d = t.getDescribe();
        if (!d.isAccessible()) return 'No access to object: ' + name;
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        for (Schema.SObjectField f : d.fields.getMap().values()) {
            Schema.DescribeFieldResult fr = f.getDescribe();
            if (!fr.isAccessible()) continue;
            fields.add(new Map<String, Object>{
                'api' => fr.getName(), 'label' => fr.getLabel(), 'type' => String.valueOf(fr.getType())
            });
        }
        return JSON.serialize(new Map<String, Object>{ 'object' => d.getName(), 'fields' => fields });
    }

    private static String soqlQuery(Map<String, Object> input) {
        String soql = (String) input.get('soql');
        if (String.isBlank(soql)) return 'soql is required.';

        String lower = soql.trim().toLowerCase();
        if (!lower.startsWith('select')) return 'Only SELECT queries are allowed.';

        if (Pattern.compile(BLOCKED_FIELDS_RE).matcher(soql).find()) {
            return 'That query references restricted personal fields (SSN / date of birth) and was blocked. Re-run without those fields.';
        }

        // An overall aggregate (aggregate function with no GROUP BY) cannot use LIMIT
        Boolean hasGroupBy   = lower.contains(' group by ');
        Boolean hasAggregate = Pattern.compile('(?i)\\b(count|sum|avg|min|max|count_distinct)\\s*\\(').matcher(lower).find();
        Boolean overallAggregate = hasAggregate && !hasGroupBy;

        if (!lower.contains(' limit ') && !overallAggregate) {
            soql += ' LIMIT ' + MAX_ROWS;
        }

        List<SObject> rows = Database.query(soql, AccessLevel.USER_MODE);
        List<Object> out = new List<Object>();
        Boolean isAgg = !rows.isEmpty() && rows[0] instanceof AggregateResult;

        if (isAgg) {
            List<String> aliases = parseAliases(soql);
            for (SObject r : rows) {
                AggregateResult ar = (AggregateResult) r;
                Map<String, Object> m = new Map<String, Object>();
                for (String a : aliases) {
                    try { m.put(a, ar.get(a)); } catch (Exception ignore) {}
                }
                out.add(m);
            }
        } else {
            for (SObject r : rows) out.add(r.getPopulatedFieldsAsMap());
        }
        return JSON.serialize(new Map<String, Object>{ 'rowCount' => rows.size(), 'rows' => out });
    }

    // Parse SELECT-clause aliases so aggregate results can be returned as named values
    private static List<String> parseAliases(String soql) {
        String lower = soql.toLowerCase();
        Integer si = lower.indexOf('select') + 6;
        Integer fi = lower.indexOf(' from ');
        String cols = soql.substring(si, fi);
        List<String> aliases = new List<String>();
        Integer exprN = 0;
        for (String part : splitTopLevel(cols)) {
            String tkn = part.trim();
            List<String> toks = tkn.split('\\s+');
            if (toks.size() > 1) {
                aliases.add(toks[toks.size() - 1]);            // explicit alias
            } else if (tkn.contains('(')) {
                aliases.add('expr' + exprN); exprN++;           // unaliased aggregate
            } else {
                aliases.add(tkn);                               // plain grouped field
            }
        }
        return aliases;
    }

    private static List<String> splitTopLevel(String s) {
        List<String> out = new List<String>();
        Integer depth = 0, start = 0;
        for (Integer i = 0; i < s.length(); i++) {
            String ch = s.substring(i, i + 1);
            if (ch == '(') depth++;
            else if (ch == ')') depth--;
            else if (ch == ',' && depth == 0) { out.add(s.substring(start, i)); start = i + 1; }
        }
        out.add(s.substring(start));
        return out;
    }

    private static String runReport(Map<String, Object> input) {
        String devName = (String) input.get('reportDeveloperName');
        if (String.isBlank(devName)) return 'reportDeveloperName is required.';
        List<Report> reps = [SELECT Id, Name FROM Report WHERE DeveloperName = :devName LIMIT 1];
        if (reps.isEmpty()) return 'No report found with developer name: ' + devName;

        Reports.ReportResults results = Reports.ReportManager.runReport(reps[0].Id, false);
        String grandTotal;
        Map<String, Reports.ReportFact> factMap = results.getFactMap();
        if (factMap != null && factMap.containsKey('T!T')) {
            Reports.ReportFactWithDetails fact = (Reports.ReportFactWithDetails) factMap.get('T!T');
            List<Reports.SummaryValue> aggs = fact.getAggregates();
            if (aggs != null && !aggs.isEmpty()) grandTotal = aggs[0].getLabel();
        }
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        return JSON.serialize(new Map<String, Object>{
            'reportName' => reps[0].Name,
            'grandTotal' => grandTotal,
            'reportUrl'  => baseUrl + '/lightning/r/Report/' + reps[0].Id + '/view'
        });
    }

    // US72: reads the firm's APPROVED objection-handling playbook (FAQ knowledge base).
    // Only Approved entries are servable; drafts/retired are intentionally excluded.
    private static String faqLookup(Map<String, Object> input) {
        String objectionType = (String) input.get('objectionType');
        String kw = input.get('keyword') == null ? '' : ((String) input.get('keyword')).toLowerCase();

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (FAQ_Entry__c e : [
            SELECT Title__c, Category__c, Objection_Type__c, Recommended_Response__c,
                   Handled_Success_Rate__c, Frequency__c
            FROM FAQ_Entry__c
            WHERE Status__c = 'Approved'
            ORDER BY Frequency__c DESC NULLS LAST
            LIMIT 100
        ]) {
            if (String.isNotBlank(objectionType) && e.Objection_Type__c != objectionType) continue;
            if (kw != '' && String.isBlank(objectionType)) {
                String hay = ((e.Title__c == null ? '' : e.Title__c) + ' ' +
                              (e.Objection_Type__c == null ? '' : e.Objection_Type__c) + ' ' +
                              (e.Recommended_Response__c == null ? '' : e.Recommended_Response__c)).toLowerCase();
                if (!hay.contains(kw)) continue;
            }
            out.add(new Map<String, Object>{
                'title' => e.Title__c,
                'objectionType' => e.Objection_Type__c,
                'successRate' => e.Handled_Success_Rate__c,
                'timesSeen' => e.Frequency__c,
                'recommendedResponse' => e.Recommended_Response__c
            });
            if (out.size() >= 10) break;
        }
        return JSON.serialize(new Map<String, Object>{ 'count' => out.size(), 'entries' => out });
    }

    // US70: the firm's most recent conversion-forecast run (all horizons).
    private static String conversionForecast(Map<String, Object> input) {
        List<Conversion_Forecast__c> latest = [
            SELECT Generated_At__c FROM Conversion_Forecast__c
            ORDER BY Generated_At__c DESC NULLS LAST LIMIT 1
        ];
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (!latest.isEmpty()) {
            DateTime gen = latest[0].Generated_At__c;
            for (Conversion_Forecast__c f : [
                SELECT Horizon_Days__c, Projected_Signed__c, Projected_Value__c, Confidence_Low__c,
                       Confidence_High__c, Narrative__c, Guardrail_Status__c, Generated_At__c
                FROM Conversion_Forecast__c
                WHERE Generated_At__c = :gen
                ORDER BY Horizon_Days__c
            ]) {
                out.add(new Map<String, Object>{
                    'horizonDays' => f.Horizon_Days__c, 'projectedSigned' => f.Projected_Signed__c,
                    'projectedValue' => f.Projected_Value__c, 'confidenceLow' => f.Confidence_Low__c,
                    'confidenceHigh' => f.Confidence_High__c, 'narrative' => f.Narrative__c,
                    'narrativeSource' => f.Guardrail_Status__c, 'generatedAt' => String.valueOf(f.Generated_At__c)
                });
            }
        }
        return JSON.serialize(new Map<String, Object>{ 'count' => out.size(), 'forecasts' => out });
    }

    // US71: lead sources ranked by quality score, with the latest per-source signing forecast.
    private static String sourceQuality(Map<String, Object> input) {
        List<Map<String, Object>> sources = new List<Map<String, Object>>();
        for (Source_Quality_Snapshot__c s : [
            SELECT Source__c, Leads__c, Signed__c, Sign_Rate__c, Lead_Fit_Rate__c, Cost_Per_Lead__c,
                   Cost_Per_Signed__c, Avg_Case_Value__c, Quality_Score__c, Score_Rationale__c
            FROM Source_Quality_Snapshot__c
            ORDER BY Quality_Score__c DESC NULLS LAST LIMIT 50
        ]) {
            sources.add(new Map<String, Object>{
                'source' => s.Source__c, 'leads' => s.Leads__c, 'signed' => s.Signed__c,
                'signRate' => s.Sign_Rate__c, 'leadFitRate' => s.Lead_Fit_Rate__c,
                'costPerLead' => s.Cost_Per_Lead__c, 'costPerSigned' => s.Cost_Per_Signed__c,
                'avgCaseValue' => s.Avg_Case_Value__c, 'qualityScore' => s.Quality_Score__c,
                'rationale' => s.Score_Rationale__c
            });
        }
        List<Map<String, Object>> forecasts = new List<Map<String, Object>>();
        for (Source_Forecast__c f : [
            SELECT Source__c, Horizon_Days__c, Projected_Signed__c, Confidence_Low__c, Confidence_High__c
            FROM Source_Forecast__c ORDER BY Generated_At__c DESC NULLS LAST LIMIT 50
        ]) {
            forecasts.add(new Map<String, Object>{
                'source' => f.Source__c, 'horizonDays' => f.Horizon_Days__c,
                'projectedSigned' => f.Projected_Signed__c,
                'confidenceLow' => f.Confidence_Low__c, 'confidenceHigh' => f.Confidence_High__c
            });
        }
        return JSON.serialize(new Map<String, Object>{ 'sources' => sources, 'forecasts' => forecasts });
    }
}