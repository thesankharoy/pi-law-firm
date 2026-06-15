public with sharing class IntakeTimeDashboardController {

    // Get Active Intake Record Type
    private static Id getActiveIntakeRT() {
        return Schema.SObjectType.Intake__c
            .getRecordTypeInfosByDeveloperName()
            .get('Active_Intake')
            .getRecordTypeId();
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

    // SEARCH INTAKES
    @AuraEnabled(cacheable=true)
    public static List<IntakeWrapper> searchIntakes(String searchKey) {

        String key = '%' + (searchKey == null ? '' : searchKey) + '%';
        Id rtId = getActiveIntakeRT();

        List<Intake__c> records = [
            SELECT Id, Name, Status__c,
                   Time_in_New__c,
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
            AND Name LIKE :key
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];

        List<IntakeWrapper> result = new List<IntakeWrapper>();

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

            result.add(new IntakeWrapper(
                i.Id,
                i.Name,
                i.Status__c,
                totalDays,
                totalMinutes,
                formatTime(totalMinutes)
            ));
        }

        return result;
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