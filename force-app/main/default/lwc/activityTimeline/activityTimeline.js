import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTimeline from '@salesforce/apex/ActivityTimelineController.getTimeline';
import USER_ID from '@salesforce/user/Id';
import { refreshApex } from '@salesforce/apex';
export default class ActivityTimeline extends NavigationMixin(LightningElement) {

@api recordId;

timelineData = [];
filteredData = [];
searchKey = '';
currentUserId = USER_ID;
wiredResult;

   @wire(getTimeline, { recordId: '$recordId' })
wiredData(result) {

    this.wiredResult = result;

    const { data, error } = result;

    if (data) {

        this.timelineData = data.map(group => {

            return {
                ...group,
                expanded: true,
                iconName: 'utility:chevrondown',
                activities: group.activities.map(act => {
                    return {
                        ...act,
                        expanded: false,
                        detailIcon: 'utility:chevronright'
                    };
                })
            };
        });

        this.filteredData = [...this.timelineData];

    } else if (error) {
        console.error(error);
    }
}

handleOpenRecord(event) {

    event.stopPropagation();

    const recordId =
        event.currentTarget.dataset.id;

    this[NavigationMixin.GenerateUrl]({

        type: 'standard__recordPage',

        attributes: {

            recordId: recordId,

            actionName: 'view'
        }

    }).then(url => {

        window.open(url, '_blank');
    });
}
handleRefresh() {

    this.isLoading = true;

    refreshApex(this.wiredResult)
        .then(() => {
            console.log('Timeline refreshed successfully');
        })
        .catch(error => {
            console.error('Refresh failed:', error);
        })
        .finally(() => {
            this.isLoading = false;
        });
}


get monthList() {

    return this.timelineData.map(
        item => item.monthYear
    );
}

toggleActivity(event) {

const recordId =
    event.currentTarget.dataset.id;

this.filteredData =
    this.filteredData.map(group => {

        group.activities =
            group.activities.map(act => {

                if(act.recordId === recordId){

                    act.expanded =
                        !act.expanded;

                    act.detailIcon =
                        act.expanded
                            ? 'utility:chevrondown'
                            : 'utility:chevronright';
                }

                return {...act};
            });

        return {...group};
    });
}
toggleSection(event) {

const selectedMonth =
    event.currentTarget.dataset.month;

this.filteredData =
    this.filteredData.map(group => {

        if(group.monthYear === selectedMonth){

            group.expanded =
                !group.expanded;

            group.iconName =
                group.expanded
                    ? 'utility:chevrondown'
                    : 'utility:chevronright';
        }

        return {...group};
    });
}
handleSearch(event) {

    this.searchKey =
        event.target.value.toLowerCase();

    if (!this.searchKey) {

        this.filteredData =
            [...this.timelineData];

        return;
    }

    let results = [];

    this.timelineData.forEach(group => {

        let activities =
            group.activities.filter(act => {

                return (
                    act.subject &&
                    act.subject
                        .toLowerCase()
                        .includes(this.searchKey)
                );

            });

        if (activities.length) {

            results.push({

monthYear: group.monthYear,

activities: [...activities],

expanded: group.expanded,

iconName: group.iconName
});
        }
    });

    this.filteredData = results;
}

showFilter = false;

selectedDate = 'all';

selectedTypes = ['Task','Call','Email','Event'];

dateOptions = [
{ label: 'All Time', value: 'all' },
{ label: 'Past', value: 'past' },
{ label: 'Future', value: 'future' }
];

activityOptions = [
{ label: 'Task', value: 'Task' },
{ label: 'Call', value: 'Call' },
{ label: 'Email', value: 'Email' },
{ label: 'Event', value: 'Event' }
];
toggleFilter() {
this.showFilter = !this.showFilter;
}

handleDateFilter(event) {
this.selectedDate = event.detail.value;
}

handleTypeFilter(event) {
this.selectedTypes = event.detail.value;
}

applyFilter() {

console.log('Current User:', this.currentUserId);
console.log('Selected User:', this.selectedUser);

this.filteredData = this.timelineData.map(group => {

    const activities = group.activities.filter(act => {

        console.log(
            'Subject:',
            act.subject,
            'Owner:',
            act.ownerId
        );

        const typeMatch =
            this.selectedTypes.includes(act.type);

        const userMatch =
            this.selectedUser === 'all'
                ? true
                : act.ownerId &&
                    act.ownerId.substring(0,15) ===
                    this.currentUserId.substring(0,15);

        return typeMatch && userMatch;

    });

    return {
        ...group,
        activities
    };

}).filter(group => group.activities.length > 0);

this.showFilter = false;
}

selectedUser = 'all';

userOptions = [
{ label: 'All Activities', value: 'all' },
{ label: 'My Activities', value: 'mine' }
];

handleUserFilter(event) {

this.selectedUser = event.detail.value;

console.log(
    'Selected User Changed:',
    this.selectedUser
);
}

selectedDate = 'all';

handleDateFilter(event) {

this.selectedDate =
    event.target.dataset.value;
}

get allTimeClass() {

return this.selectedDate === 'all'
    ? 'date-btn active'
    : 'date-btn';
}

get pastClass() {

return this.selectedDate === 'past'
    ? 'date-btn active'
    : 'date-btn';
}

get futureClass() {

return this.selectedDate === 'future'
    ? 'date-btn active'
    : 'date-btn';
}
showNoDate = false;

handleNoDateChange(event) {

this.showNoDate =
    event.target.checked;
}
}