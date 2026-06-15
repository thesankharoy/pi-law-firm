trigger IntakeQualityTrigger on Intake__c (before insert, before update) {
    for (Intake__c intake : Trigger.new) {
        Decimal score = intake.Qualification_Score__c;
        
        if (score == null) {
            intake.Case_Quality__c = 'Cold';
        } else if (score >= 76) {
            intake.Case_Quality__c = 'Hot';
        } else if (score >= 51) {
            intake.Case_Quality__c = 'Warm';
        } else {
            intake.Case_Quality__c = 'Cold';
        }
    }
}