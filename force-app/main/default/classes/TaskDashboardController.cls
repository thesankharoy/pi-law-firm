public class TaskDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<TaskWrapper> getWeeklyTasks() {

        Date startDate = Date.today().addDays(-7);  

        List<Task> tasks = [
            SELECT Id, Subject, Status, ActivityDate, CreatedDate, IsClosed
            FROM Task
            WHERE CreatedDate = LAST_N_DAYS:7
            ORDER BY CreatedDate DESC
        ];

        List<TaskWrapper> result = new List<TaskWrapper>();

        for (Task t : tasks) {
            result.add(new TaskWrapper(t));
        }

        return result;
    }

    public class TaskWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public Boolean isCompleted;
        @AuraEnabled public DateTime createdDate;

        public TaskWrapper(Task t) {
            id = t.Id;
            subject = t.Subject;
            status = t.Status;
            activityDate = t.ActivityDate;
            createdDate = t.CreatedDate;

            // ✅ FIXED LOGIC
            isCompleted = t.IsClosed;
        }
    }
}