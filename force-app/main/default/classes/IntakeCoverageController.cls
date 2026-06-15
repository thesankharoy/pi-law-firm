public with sharing class IntakeCoverageController {

    public class CoverageDTO {

        @AuraEnabled
        public Integer afterHoursCount;

        @AuraEnabled
        public Integer coveredCount;

        @AuraEnabled
        public Integer missedCount;

        @AuraEnabled
        public Decimal coverageRate;
    }

    @AuraEnabled(cacheable=true)
    public static CoverageDTO getCoverageData() {

        CoverageDTO dto =
            new CoverageDTO();

        dto.afterHoursCount = 0;
        dto.coveredCount = 0;
        dto.missedCount = 0;

        List<Intake__c> intakes = [

            SELECT Id,
                   CreatedDate,
                   First_Response_DateTime__c

            FROM Intake__c
        ];

        for(Intake__c intake : intakes){

            Datetime createdDt =
                intake.CreatedDate;

            Integer dayNum =
                createdDt.date().toStartOfWeek()
                .daysBetween(
                    createdDt.date()
                );

            Integer hour =
                createdDt.hour();

            Boolean isWeekend =
                (dayNum == 5 || dayNum == 6);

            Boolean isAfterHours =
                hour < 9 || hour >= 18;

            if(isWeekend || isAfterHours){

                dto.afterHoursCount++;

                if(intake.First_Response_DateTime__c != null){

                    Long diffMs =
                        intake.First_Response_DateTime__c.getTime()
                        - createdDt.getTime();

                    Decimal mins =
                        diffMs /
                        (1000 * 60);

                    if(mins <= 30){

                        dto.coveredCount++;
                    }
                    else{

                        dto.missedCount++;
                    }
                }
                else{

                    dto.missedCount++;
                }
            }
        }

        dto.coverageRate =

            dto.afterHoursCount > 0

            ?

            ((Decimal)dto.coveredCount
            / dto.afterHoursCount) * 100

            : 0;

        return dto;
    }
}