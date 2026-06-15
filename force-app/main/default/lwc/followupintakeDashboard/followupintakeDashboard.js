import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getIntakes from '@salesforce/apex/IntakeAnalyticsController.getIntakes';

export default class IntakeDashboard extends NavigationMixin(LightningElement) {

    @track intakes = [];

    pageSize = 5;
    pageNumber = 1;
    totalRecords = 0;
    totalPages = 0;

    connectedCallback() {
        this.loadData();
    }

    loadData() {
        getIntakes({
            pageSize: this.pageSize,
            pageNumber: this.pageNumber
        })
        .then(result => {

            this.intakes = result.records.map(item => {
                return {
                    ...item,
                    statusText: item.noFollowUp ? 'No Follow-up' : 'Followed',
                    rowClass: item.noFollowUp ? 'flash-row danger' : 'flash-row success'
                };
            });

            this.totalRecords = result.totalRecords;
            this.totalPages = Math.ceil(this.totalRecords / this.pageSize);

        })
        .catch(error => {
            console.error(error);
        });
    }

    nextPage() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.loadData();
        }
    }

    prevPage() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.loadData();
        }
    }

    openRecord(event) {
        const recordId = event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Intake__c',
                actionName: 'view'
            }
        });
    }
}