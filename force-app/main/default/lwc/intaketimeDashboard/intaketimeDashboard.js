import { LightningElement, track } from 'lwc';
import searchIntakes from '@salesforce/apex/IntakeTimeDashboardController.searchIntakes';
import getAverageIntakeTime from '@salesforce/apex/IntakeTimeDashboardController.getAverageIntakeTime';
import { NavigationMixin } from 'lightning/navigation';

export default class IntakeDashboard extends NavigationMixin(LightningElement) {

    @track intakes = [];
    @track formattedAverageTime = '';

    connectedCallback() {
        this.loadAverage();
        this.loadData();
    }

    loadData() {
        searchIntakes({ searchKey: '' })
            .then(result => {
                this.intakes = result;
                console.log('data =>', result);
            })
            .catch(error => console.error(error));
    }

    handleSearch(event) {
        searchIntakes({ searchKey: event.target.value })
            .then(result => {
                this.intakes = result;
            })
            .catch(error => console.error(error));
    }

    loadAverage() {
        getAverageIntakeTime()
            .then(result => {
                this.formattedAverageTime = result;
                console.log('Formated Avg=>'+this.formattedAverageTime);
            })
            .catch(error => console.error(error));
    }

    openRecord(event) {
        const recordId = event.target.dataset.id;
        console.log('Formated Avg=>'+recordId);
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Intake__c',
                actionName: 'view'
            }
        });
    }
}