public with sharing class IntakeCoverageController {

    public class CoverageDTO {
        @AuraEnabled public Integer afterHoursCount;
        @AuraEnabled public Integer coveredCount;
        @AuraEnabled public Integer missedCount;
        @AuraEnabled public Decimal coverageRate;
    }

    @AuraEnabled(cacheable=true)
    public static CoverageDTO getCoverageData() {
        CoverageDTO dto = new CoverageDTO();
        dto.afterHoursCount = 0;
        dto.coveredCount = 0;
        dto.missedCount = 0;

        // one authoritative definition of "open" — same as the response-time dashboard
        BusinessHours bh = [SELECT Id FROM BusinessHours WHERE IsDefault = true LIMIT 1];

        List<Intake__c> intakes = [
            SELECT Id, CreatedDate, First_Response_DateTime__c
            FROM Intake__c
        ];

        for (Intake__c intake : intakes) {

            // after-hours = created OUTSIDE business hours (respects weekends + holidays + timezone)
            Boolean isAfterHours = !BusinessHours.isWithin(bh.Id, intake.CreatedDate);
            if (!isAfterHours) {
                continue;
            }

            dto.afterHoursCount++;

            if (intake.First_Response_DateTime__c != null) {
                Long diffMs = intake.First_Response_DateTime__c.getTime()
                            - intake.CreatedDate.getTime();
                Decimal mins = diffMs / (1000.0 * 60.0);
                if (mins <= 30) {
                    dto.coveredCount++;
                } else {
                    dto.missedCount++;
                }
            } else {
                dto.missedCount++;
            }
        }

        dto.coverageRate = dto.afterHoursCount > 0
            ? (((Decimal) dto.coveredCount / dto.afterHoursCount) * 100).setScale(1, System.RoundingMode.HALF_UP)
            : 0;

        return dto;
    }
}