import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDashboardData from '@salesforce/apex/AISentimentDashboardController.getDashboardData';

export default class AiSentimentDashboard extends NavigationMixin(LightningElement) {

    //=============================
    // Variables
    //=============================

    @track dashboard = {
        totalIntakes: 0,
        totalCalls: 0,
        averageSentiment: '',
        records: []
    };

    isLoading = false;

    pageNumber = 1;
    pageSize = 7;
    totalRecords = 0;

    selectedFilter = 'All';
    

    //=============================
    // Filter Options
    //=============================

    filterOptions = [
        { label: 'All', value: 'All' },
        { label: 'Today', value: 'Today' },
        { label: 'Yesterday', value: 'Yesterday' },
        { label: 'This Month', value: 'This Month' },
        { label: 'Last Month', value: 'Last Month' }
    ];

openRecord(event) {

    const recordId = event.currentTarget.dataset.id;

    console.log('Record Id:', recordId);

    this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
            recordId: recordId,
            objectApiName: 'Intake__c',
            actionName: 'view'
        }
    });

}

    //=============================
    // Page Load
    //=============================

    connectedCallback() {
        this.loadDashboard();
    }

    //=============================
    // Load Dashboard
    //=============================

    loadDashboard() {

        this.isLoading = true;

        getDashboardData({
            filterType: this.selectedFilter,
            pageNumber: this.pageNumber
        })
        .then(result => {

            this.dashboard = result;

            this.totalRecords = result.totalRecords;

            this.pageSize = result.pageSize;

            console.log('Dashboard Result', JSON.stringify(result));
            console.log('Records', JSON.stringify(result.records));

            // Add UI-only properties
                   const records = result.records.map(item => {

                    const sentiment = (item.sentiment || '').trim().toLowerCase();

                    let sentimentClass = 'sentiment-neutral';

                    if (sentiment === 'positive') {
                        sentimentClass = 'sentiment-positive';
                    } else if (sentiment === 'negative') {
                        sentimentClass = 'sentiment-negative';
                    }

                    return {
                        ...item,
                        sentimentClass
                    };
                });

                this.dashboard = {
                    ...result,
                    records
                };

                console.log(this.dashboard.records);

        })
        .catch(error => {

            console.error('Dashboard Error', error);

        })
        .finally(() => {

            this.isLoading = false;

        });

    }

    //=============================
    // Filter Change
    //=============================

    handleFilter(event) {

        this.selectedFilter = event.detail.value;

        this.pageNumber = 1;

        this.loadDashboard();

    }

    //=============================
    // Previous Page
    //=============================

    previousPage() {

        if (this.pageNumber > 1) {

            this.pageNumber--;

            this.loadDashboard();

        }

    }

    //=============================
    // Next Page
    //=============================

    nextPage() {

        if ((this.pageNumber * this.pageSize) < this.totalRecords) {

            this.pageNumber++;

            this.loadDashboard();

        }

    }

    //=============================
    // Getters
    //=============================

    get disablePrevious() {

        return this.pageNumber === 1;

    }

    get disableNext() {

        return (this.pageNumber * this.pageSize) >= this.totalRecords;

    }

}