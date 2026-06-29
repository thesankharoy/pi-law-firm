public with sharing class DashboardController {

    @AuraEnabled(cacheable=true)
    public static List<SelectOptionWrapper> getOwners() {

        List<SelectOptionWrapper> options = new List<SelectOptionWrapper>();

        options.add(new SelectOptionWrapper('All Owners', 'all'));

        for(User u : [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
            ORDER BY Name
        ]) {
            options.add(new SelectOptionWrapper(u.Name, u.Id));
        }

        return options;
    }

    public class SelectOptionWrapper {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public SelectOptionWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}