public with sharing class ActivityTimelineController {

    public class ActivityItem {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String ownerInitials;
        @AuraEnabled public String type;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public String displayDate;
        @AuraEnabled public String iconName;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String description;
    }

    public class MonthGroup {
        @AuraEnabled public String monthYear;
        @AuraEnabled public Boolean expanded;
        @AuraEnabled public List<ActivityItem> activities;
    }

    @AuraEnabled(cacheable=true)
    public static List<MonthGroup> getTimeline(Id recordId) {

        List<ActivityItem> allActivities = new List<ActivityItem>();

        List<String> months = new List<String>{
            'Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'
        };

        /* TASKS / CALLS / EMAILS */

        for(Task t : [
            SELECT Id,
                   Subject,
                   Status,
                   Description,
                   ActivityDate,
                   TaskSubtype,
                   OwnerId,
                   Owner.FirstName,
                   Owner.LastName
            FROM Task
            WHERE WhatId = :recordId
            ORDER BY ActivityDate DESC
        ]) {

            ActivityItem item = new ActivityItem();

            item.recordId = t.Id;
            item.subject = t.Subject;
            item.status = t.Status;
            item.activityDate = t.ActivityDate;
            item.ownerId = t.OwnerId;
            item.description = t.Description;

            if(t.ActivityDate != null){
                item.displayDate =
                    months[t.ActivityDate.month()-1] +
                    ' ' +
                    String.valueOf(t.ActivityDate.day());
            }

            String initials = '';

            if(t.Owner.FirstName != null){
                initials += t.Owner.FirstName.substring(0,1);
            }

            if(t.Owner.LastName != null){
                initials += t.Owner.LastName.substring(0,1);
            }

            item.ownerInitials = initials;

            if(t.TaskSubtype == 'Call'){
                item.type = 'Call';
                item.iconName = 'standard:call';
            }
            else if(t.TaskSubtype == 'Email'){
                item.type = 'Email';
                item.iconName = 'standard:email';
            }
            else{
                item.type = 'Task';
                item.iconName = 'standard:task';
            }
            System.debug(
                    'Subject=' + item.subject +
                    ' OwnerId=' + item.ownerId
                );

            allActivities.add(item);
        }

        /* EVENTS */

        for(Event e : [
            SELECT Id,
                   Subject,
                   ActivityDate,
                   Description,
                   OwnerId,
                   Owner.FirstName,
                   Owner.LastName
            FROM Event
            WHERE WhatId = :recordId
            ORDER BY ActivityDate DESC
        ]) {

            ActivityItem item = new ActivityItem();

            item.recordId = e.Id;
            item.subject = e.Subject;
            item.status = 'Scheduled';
            item.type = 'Event';
            item.iconName = 'standard:event';
            item.ownerId = e.OwnerId;
            item.description = e.Description;
            item.activityDate = e.ActivityDate;

            if(e.ActivityDate != null){
                item.displayDate =
                    months[e.ActivityDate.month()-1] +
                    ' ' +
                    String.valueOf(e.ActivityDate.day());
            }

            String initials = '';

            if(e.Owner.FirstName != null){
                initials += e.Owner.FirstName.substring(0,1);
            }

            if(e.Owner.LastName != null){
                initials += e.Owner.LastName.substring(0,1);
            }

            item.ownerInitials = initials;
            System.debug(
                'Subject=' + item.subject +
                ' OwnerId=' + item.ownerId
            );

            allActivities.add(item);
        }

        /* SORT DESCENDING */

        allActivities.sort(new ActivityDateSorter());

        /* GROUP BY MONTH */

        Map<String,List<ActivityItem>> groupedMap =
            new Map<String,List<ActivityItem>>();

        for(ActivityItem item : allActivities){

            if(item.activityDate == null){
                continue;
            }

            String monthYear =
                months[item.activityDate.month()-1]
                + ' '
                + String.valueOf(item.activityDate.year());

            if(!groupedMap.containsKey(monthYear)){
                groupedMap.put(
                    monthYear,
                    new List<ActivityItem>()
                );
            }

            groupedMap.get(monthYear).add(item);
        }

        /* BUILD RESULT */

        List<MonthGroup> result =
            new List<MonthGroup>();

        for(String key : groupedMap.keySet()){

            MonthGroup monthGroup =
                new MonthGroup();

            monthGroup.monthYear = key;
            monthGroup.expanded = true;
            monthGroup.activities =
                groupedMap.get(key);

            result.add(monthGroup);
        }

        return result;
    }

    /* SORTER */

    public class ActivityDateSorter
        implements Comparator<ActivityItem>{

        public Integer compare(
            ActivityItem a,
            ActivityItem b
        ){

            if(a.activityDate == b.activityDate){
                return 0;
            }

            if(a.activityDate > b.activityDate){
                return -1;
            }

            return 1;
        }
    }
}