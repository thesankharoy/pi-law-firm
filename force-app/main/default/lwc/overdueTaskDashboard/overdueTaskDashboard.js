import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

import getOverdueTasks from '@salesforce/apex/OverdueTaskDashboardController.getOverdueTasks';
import getTotalTaskCount from '@salesforce/apex/OverdueTaskDashboardController.getTotalTaskCount';

export default class OverdueTaskDashboard extends NavigationMixin(LightningElement) {

    tasks = [];

    pageNumber = 1;
    pageSize = 7;
    totalCount = 0;

    connectedCallback() {
        this.loadData();
        this.loadCount();
    }

    loadCount() {
        getTotalTaskCount()
            .then(result => {
                this.totalCount = result;
            })
            .catch(error => {
                console.error('Count Error:', error);
            });
    }

    loadData() {

        getOverdueTasks({
            pageNumber: this.pageNumber
        })
        .then(result => {

            this.tasks = result.map(row => {

                // STATUS CLASS
                let statusClass = 'status-notstarted';

                if (row.status === 'Incomplete') {
                    statusClass = 'status-incomplete';
                }
                else if (row.status === 'Completed') {
                    statusClass = 'status-completed';
                }

                // DAYS OVER CLASS
                let daysClass = 'days-over-orange';

                if (row.ageDays >= 10) {
                    daysClass = 'days-over-red';
                }

                return {
                    ...row,
                    statusClass,
                    daysClass
                };
            });

        })
        .catch(error => {
            console.error('Task Error:', error);
        });
    }

    get totalPages() {
        return Math.ceil(this.totalCount / this.pageSize);
    }

    get disablePrevious() {
        return this.pageNumber <= 1;
    }

    get disableNext() {
        return this.pageNumber >= this.totalPages;
    }

    handlePrevious() {

        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.loadData();
        }
    }

    handleNext() {

        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.loadData();
        }
    }

    handleRefresh() {
        this.loadData();
        this.loadCount();
    }

    handleOpenRecord(event) {

        const recordId = event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Task',
                actionName: 'view'
            }
        });
    }

    get totalRecords() {
        return this.totalCount;
    }
}