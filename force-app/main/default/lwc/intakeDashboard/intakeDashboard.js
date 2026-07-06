import { LightningElement } from 'lwc';
import getTotalLeadsEntered from '@salesforce/apex/IntakeDashboardController.getTotalLeadsEntered';
import getSignedClients from '@salesforce/apex/IntakeDashboardController.getSignedClients';
import getConversionRate from '@salesforce/apex/IntakeDashboardController.getConversionRate';
import getOverallConversionRate from '@salesforce/apex/IntakeDashboardController.getOverallConversionRate';

export default class IntakeDashboard extends LightningElement {

    totalLeads = 0;
    signedClients = 0;
    conversionRate = 0;
    overallConversionRate = 0;

    selectedDateFilter = 'THIS_MONTH';
    customStartDate = null;
    customEndDate = null;
    customError = '';

    get dateFilterOptions() {
        return [
            { label: 'Today', value: 'TODAY' },
            { label: 'Yesterday', value: 'YESTERDAY' },
            { label: 'This Week', value: 'THIS_WEEK' },
            { label: 'Last Week', value: 'LAST_WEEK' },
            { label: 'This Month', value: 'THIS_MONTH' },
            { label: 'Last Month', value: 'LAST_MONTH' },
            { label: 'This Quarter', value: 'THIS_QUARTER' },
            { label: 'Last Quarter', value: 'LAST_QUARTER' },
            { label: 'This Year', value: 'THIS_YEAR' },
            { label: 'Last Year', value: 'LAST_YEAR' },
            { label: 'Custom Range…', value: 'CUSTOM' }
        ];
    }

    get showCustomRange() {
        return this.selectedDateFilter === 'CUSTOM';
    }

    connectedCallback() {
        this.loadDashboardData();
        this.loadOverallConversionRate();
    }

    handleDateFilterChange(event) {
        this.selectedDateFilter = event.detail.value;
        this.customError = '';
        // For presets, load immediately. For custom, wait until the user clicks Apply.
        if (this.selectedDateFilter !== 'CUSTOM') {
            this.loadDashboardData();
        }
    }

    handleStartDateChange(event) {
        this.customStartDate = event.detail.value;
    }

    handleEndDateChange(event) {
        this.customEndDate = event.detail.value;
    }

    handleApplyCustom() {
        if (!this.customStartDate || !this.customEndDate) {
            this.customError = 'Please select both a start and end date.';
            return;
        }
        if (this.customStartDate > this.customEndDate) {
            this.customError = 'Start date must be on or before the end date.';
            return;
        }
        this.customError = '';
        this.loadDashboardData();
    }

    loadDashboardData() {
        const params = {
            dateFilter: this.selectedDateFilter,
            startDate: this.selectedDateFilter === 'CUSTOM' ? this.customStartDate : null,
            endDate: this.selectedDateFilter === 'CUSTOM' ? this.customEndDate : null
        };

        getTotalLeadsEntered(params)
            .then(result => { this.totalLeads = result; })
            .catch(error => console.error('Total leads error', error));

        getSignedClients(params)
            .then(result => { this.signedClients = result; })
            .catch(error => console.error('Signed clients error', error));

        getConversionRate(params)
            .then(result => { this.conversionRate = Number(result).toFixed(2); })
            .catch(error => console.error('Conversion error', error));
    }
    loadOverallConversionRate() {
    getOverallConversionRate()
        .then(result => {
            this.overallConversionRate = result;
        })
        .catch(error => {
            console.error('Error loading overall conversion rate', error);
        });
}
}