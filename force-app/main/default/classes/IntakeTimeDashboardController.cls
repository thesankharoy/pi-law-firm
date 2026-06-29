public with sharing class IntakeTimeDashboardController {

    // Get Active Intake Record Type
    private static Id getActiveIntakeRT() {
        return Schema.SObjectType.Intake__c
            .getRecordTypeInfosByDeveloperName()
            .get('Active_Intake')
            .getRecordTypeId();
    }
    public class IntakePageResult {
    @AuraEnabled public List<IntakeWrapper> records;
    @AuraEnabled public Integer totalRecords;
    @AuraEnabled public Integer pageNumber;
    @AuraEnabled public Integer pageSize;
    @AuraEnabled public Integer totalPages;

    public IntakePageResult() {
        records = new List<IntakeWrapper>();
    }
}

    // FORMAT FUNCTION (minutes → readable)
    private static String formatTime(Long minutes) {

        if (minutes == null || minutes == 0) {
            return '0 Min';
        }

        Long days = minutes / 1440;
        Long hours = Math.mod(minutes, 1440) / 60;
        Long mins = Math.mod(minutes, 60);

        return days + ' Days ' + hours + ' Hours ' + mins + ' Minutes';
    }
@AuraEnabled(cacheable=true)
public static IntakePageResult searchIntakes(
    String searchKey,
    Integer pageNumber,
    Integer pageSize,
    String selectedMonth,
    String dateFilter
) {

    if(pageNumber == null || pageNumber < 1){
        pageNumber = 1;
    }

    if(pageSize == null || pageSize < 1){
        pageSize = 5;
    }

    String key = '%' + (searchKey == null ? '' : searchKey.trim()) + '%';

    Id rtId = getActiveIntakeRT();

    Integer offsetRows = (pageNumber - 1) * pageSize;

    List<String> conditions = new List<String>();
    conditions.add('RecordTypeId = :rtId');
    conditions.add('Name LIKE :key');

    /* Month Filter */

    if(String.isNotBlank(selectedMonth)){
        Integer monthNum = Integer.valueOf(selectedMonth);
        conditions.add(
            'CALENDAR_MONTH(CreatedDate) = ' + monthNum
        );
    }

    /* Date Filter */

    if(String.isNotBlank(dateFilter)){

        if(dateFilter == 'TODAY'){
            conditions.add('CreatedDate = TODAY');
        }
        else if(dateFilter == 'YESTERDAY'){
            conditions.add('CreatedDate = YESTERDAY');
        }
        else if(dateFilter == 'TOMORROW'){
            conditions.add('CreatedDate = TOMORROW');
        }
        else if(dateFilter == 'THIS_WEEK'){
            conditions.add('CreatedDate = THIS_WEEK');
        }
        else if(dateFilter == 'LAST_WEEK'){
            conditions.add('CreatedDate = LAST_WEEK');
        }
        else if(dateFilter == 'NEXT_WEEK'){
            conditions.add('CreatedDate = NEXT_WEEK');
        }
        else if(dateFilter == 'THIS_MONTH'){
            conditions.add('CreatedDate = THIS_MONTH');
        }
        else if(dateFilter == 'LAST_MONTH'){
            conditions.add('CreatedDate = LAST_MONTH');
        }
        else if(dateFilter == 'NEXT_MONTH'){
            conditions.add('CreatedDate = NEXT_MONTH');
        }
        else if(dateFilter == 'THIS_QUARTER'){
            conditions.add('CreatedDate = THIS_QUARTER');
        }
        else if(dateFilter == 'LAST_QUARTER'){
            conditions.add('CreatedDate = LAST_QUARTER');
        }
        else if(dateFilter == 'NEXT_QUARTER'){
            conditions.add('CreatedDate = NEXT_QUARTER');
        }
        else if(dateFilter == 'THIS_YEAR'){
            conditions.add('CreatedDate = THIS_YEAR');
        }
        else if(dateFilter == 'LAST_YEAR'){
            conditions.add('CreatedDate = LAST_YEAR');
        }
    }

    String whereClause =
        ' WHERE ' + String.join(conditions, ' AND ');

    /* Count Query */

    String countQuery =
        'SELECT COUNT() FROM Intake__c' +
        whereClause;

    Integer totalRecords =
        Database.countQuery(countQuery);

    /* Data Query */

    String dataQuery =
        'SELECT Id,' +
        ' Name,' +
        ' Status__c,' +
        ' Time_in_New__c,' +
        ' Time_in_Open__c,' +
        ' Time_in_Working__c,' +
        ' Time_in_Under_Review__c,' +
        ' Time_in_Qualified__c,' +
        ' Time_in_Retainer_Sent__c,' +
        ' Time_in_Retainer_Signed__c,' +
        ' Time_in_Turned_Down__c,' +
        ' Time_in_Converted__c ' +
        'FROM Intake__c ' +
        whereClause +
        ' ORDER BY CreatedDate DESC ' +
        ' LIMIT ' + pageSize +
        ' OFFSET ' + offsetRows;

    List<Intake__c> records =
        Database.query(dataQuery);

    IntakePageResult response = new IntakePageResult();

    response.records = new List<IntakeWrapper>();
    response.totalRecords = totalRecords;
    response.pageNumber = pageNumber;
    response.pageSize = pageSize;
    response.totalPages =
        totalRecords == 0
        ? 1
        : (Integer)Math.ceil(
            (Decimal)totalRecords / pageSize
        );

    for(Intake__c i : records){

        Decimal totalDays =
            (i.Time_in_New__c == null ? 0 : i.Time_in_New__c) +
            (i.Time_in_Open__c == null ? 0 : i.Time_in_Open__c) +
            (i.Time_in_Working__c == null ? 0 : i.Time_in_Working__c) +
            (i.Time_in_Under_Review__c == null ? 0 : i.Time_in_Under_Review__c) +
            (i.Time_in_Qualified__c == null ? 0 : i.Time_in_Qualified__c) +
            (i.Time_in_Retainer_Sent__c == null ? 0 : i.Time_in_Retainer_Sent__c) +
            (i.Time_in_Retainer_Signed__c == null ? 0 : i.Time_in_Retainer_Signed__c) +
            (i.Time_in_Turned_Down__c == null ? 0 : i.Time_in_Turned_Down__c) +
            (i.Time_in_Converted__c == null ? 0 : i.Time_in_Converted__c);

        Long totalMinutes =
            (Long)(totalDays * 1440);

        response.records.add(
            new IntakeWrapper(
                i.Id,
                i.Name,
                i.Status__c,
                totalDays,
                totalMinutes,
                formatTime(totalMinutes)
            )
        );
    }

    return response;
}
    // AVERAGE TIME
    @AuraEnabled(cacheable=true)
    public static String getAverageIntakeTime() {

        Id rtId = getActiveIntakeRT();

        List<Intake__c> records = [
            SELECT Time_in_New__c,
                   Time_in_Open__c,
                   Time_in_Working__c,
                   Time_in_Under_Review__c,
                   Time_in_Qualified__c,
                   Time_in_Retainer_Sent__c,
                   Time_in_Retainer_Signed__c,
                   Time_in_Turned_Down__c,
                   Time_in_Converted__c
            FROM Intake__c
            WHERE RecordTypeId = :rtId
        ];

        Long totalAllMinutes = 0;
        Integer count = 0;

        for (Intake__c i : records) {

            Decimal totalDays =
                (i.Time_in_New__c == null ? 0 : i.Time_in_New__c) +
                (i.Time_in_Open__c == null ? 0 : i.Time_in_Open__c) +
                (i.Time_in_Working__c == null ? 0 : i.Time_in_Working__c) +
                (i.Time_in_Under_Review__c == null ? 0 : i.Time_in_Under_Review__c) +
                (i.Time_in_Qualified__c == null ? 0 : i.Time_in_Qualified__c) +
                (i.Time_in_Retainer_Sent__c == null ? 0 : i.Time_in_Retainer_Sent__c) +
                (i.Time_in_Retainer_Signed__c == null ? 0 : i.Time_in_Retainer_Signed__c) +
                (i.Time_in_Turned_Down__c == null ? 0 : i.Time_in_Turned_Down__c) +
                (i.Time_in_Converted__c == null ? 0 : i.Time_in_Converted__c);

            Long totalMinutes = (Long)(totalDays * 1440);

            totalAllMinutes += totalMinutes;
            count++;
        }

        if (count == 0) return '0 Min';

        return formatTime(totalAllMinutes / count);
    }

    // WRAPPER
    public class IntakeWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;

        @AuraEnabled public Decimal rawTime;      // in days
        @AuraEnabled public Long totalMinutes;    // converted
        @AuraEnabled public String formattedTime; // UI

        public IntakeWrapper(
            Id id,
            String name,
            String status,
            Decimal rawTime,
            Long totalMinutes,
            String formattedTime
        ) {
            this.id = id;
            this.name = name;
            this.status = status;
            this.rawTime = rawTime;
            this.totalMinutes = totalMinutes;
            this.formattedTime = formattedTime;
        }
    }
}