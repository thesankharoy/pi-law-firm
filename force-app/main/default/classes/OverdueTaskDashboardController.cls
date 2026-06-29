public with sharing class OverdueTaskDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<TaskWrapper> getOverdueTasks(Integer pageNumber) {

        Integer pageSize = 7;
        Integer offsetRows = (pageNumber - 1) * pageSize;

        List<TaskWrapper> results = new List<TaskWrapper>();

        List<Task> tasks = [
            SELECT Id,
                   Subject,
                   Status,
                   Priority,
                   ActivityDate,
                   Owner.Name
            FROM Task
            WHERE Status != 'Completed'
            AND ActivityDate < TODAY
            ORDER BY ActivityDate ASC
            LIMIT :pageSize
            OFFSET :offsetRows
        ];

        Date todayDate = Date.today();

        for(Task t : tasks){

            TaskWrapper w = new TaskWrapper();

            w.recordId = t.Id;
            w.subject = t.Subject;
            w.status = t.Status;
            w.priority = t.Priority;
            w.dueDate = t.ActivityDate;
            w.ownerName = t.Owner.Name;
            w.ageDays = t.ActivityDate.daysBetween(todayDate);

            results.add(w);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getTotalTaskCount(){

        return [
            SELECT COUNT()
            FROM Task
            WHERE Status != 'Completed'
            AND ActivityDate < TODAY
        ];
    }

    @AuraEnabled(cacheable=true)
    public static DashboardSummary getDashboardSummary(){

        DashboardSummary summary = new DashboardSummary();

        summary.totalOverdue = [
            SELECT COUNT()
            FROM Task
            WHERE Status != 'Completed'
            AND ActivityDate < TODAY
        ];

        summary.highPriority = [
            SELECT COUNT()
            FROM Task
            WHERE Status != 'Completed'
            AND ActivityDate < TODAY
            AND Priority = 'High'
        ];

        summary.dueToday = [
            SELECT COUNT()
            FROM Task
            WHERE Status != 'Completed'
            AND ActivityDate = TODAY
        ];

        summary.upcoming = [
            SELECT COUNT()
            FROM Task
            WHERE Status != 'Completed'
            AND ActivityDate > TODAY
        ];

        return summary;
    }

    public class TaskWrapper {

        @AuraEnabled public Id recordId;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Integer ageDays;
    }

    public class DashboardSummary {

        @AuraEnabled public Integer totalOverdue;
        @AuraEnabled public Integer highPriority;
        @AuraEnabled public Integer dueToday;
        @AuraEnabled public Integer upcoming;
    }
}