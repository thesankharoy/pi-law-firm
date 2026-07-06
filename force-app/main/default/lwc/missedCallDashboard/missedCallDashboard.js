import { LightningElement, track } from 'lwc';
import getDashboardData
from '@salesforce/apex/MissedCallDashboardController.getDashboardData';

export default class MissedCallDashboard extends LightningElement {

    @track dashboard = {};

    selectedFilter = 'TODAY';
    pageSize = 6;
    currentPage = 1;
    

    columns = [
        {
            label: 'Subject',
            fieldName: 'Subject'
        },
        {
            label: 'Disposition',
            fieldName: 'CallDisposition'
        },
        {
            label: 'Duration (Sec)',
            fieldName: 'CallDurationInSeconds',
            type: 'number'
        },
        {
            label: 'Incoming Time',
            fieldName: 'Incoming_Time__c',
            type: 'date',
            typeAttributes: {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            }
        }
    ];

    filterOptions = [
        {
            label: 'Today',
            value: 'TODAY'
        },
        {
            label: 'Last 7 Days',
            value: 'LAST7'
        },
        {
            label: 'This Month',
            value: 'MONTH'
        }
    ];

    connectedCallback() {
        this.loadData();
    }

   handleFilterChange(event) {

    this.selectedFilter = event.detail.value;

    console.log('Selected:', this.selectedFilter);

    this.loadData();
}

loadData() {

    console.log('Calling Apex with:', this.selectedFilter);

    getDashboardData({
        filterType: this.selectedFilter
    })
    .then(result => {

        console.log('Apex Result:', result);

        this.dashboard = result;
        this.currentPage = 1;

    })
    .catch(error => {

        console.error(JSON.stringify(error));

    });
}

get pagedMissedCalls() {

    if (!this.dashboard?.missedCallList) {
        return [];
    }

    const start = (this.currentPage - 1) * this.pageSize;

    return this.dashboard.missedCallList.slice(start, start + this.pageSize);
}

get totalPages() {

    if (!this.dashboard?.missedCallList?.length) {
        return 1;
    }

    return Math.ceil(this.dashboard.missedCallList.length / this.pageSize);
}

get disablePrevious() {
    return this.currentPage === 1;
}

get disableNext() {
    return this.currentPage >= this.totalPages;
}
handleNext() {

    if (this.currentPage < this.totalPages) {
        this.currentPage++;
    }

}

handlePrevious() {

    if (this.currentPage > 1) {
        this.currentPage--;
    }

}
}