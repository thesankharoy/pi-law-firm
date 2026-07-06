import { LightningElement, track } from 'lwc';
import searchIntakes from '@salesforce/apex/IntakeTimeDashboardController.searchIntakes';
import getAverageIntakeTime from '@salesforce/apex/IntakeTimeDashboardController.getAverageIntakeTime';
import { NavigationMixin } from 'lightning/navigation';

export default class IntakeDashboard extends NavigationMixin(LightningElement) {

    @track intakes = [];
    @track formattedAverageTime = '';

    @track selectedMonth;
    @track selectedDateFilter = 'THIS_MONTH';

    @track pageNumber = 1;
    @track pageSize = 5;
    @track totalPages = 0;
    @track totalRecords = 0;

    connectedCallback() {

        const currentMonth =
            String(new Date().getMonth() + 1).padStart(2, '0');

        this.selectedMonth = currentMonth;

        this.loadAverage();
        this.loadData();
    }

    /* =========================
       FILTER OPTIONS
    ========================= */

    get monthOptions() {
        return [
            { label: 'January', value: '01' },
            { label: 'February', value: '02' },
            { label: 'March', value: '03' },
            { label: 'April', value: '04' },
            { label: 'May', value: '05' },
            { label: 'June', value: '06' },
            { label: 'July', value: '07' },
            { label: 'August', value: '08' },
            { label: 'September', value: '09' },
            { label: 'October', value: '10' },
            { label: 'November', value: '11' },
            { label: 'December', value: '12' }
        ];
    }

    get dateFilterOptions() {
        return [
            { label: 'Today', value: 'TODAY' },
            { label: 'Tomorrow', value: 'TOMORROW' },
            { label: 'Yesterday', value: 'YESTERDAY' },
            { label: 'This Week', value: 'THIS_WEEK' },
            { label: 'Last Week', value: 'LAST_WEEK' },
            { label: 'Next Week', value: 'NEXT_WEEK' },
            { label: 'This Month', value: 'THIS_MONTH' },
            { label: 'Last Month', value: 'LAST_MONTH' },
            { label: 'Next Month', value: 'NEXT_MONTH' },
            { label: 'This Quarter', value: 'THIS_QUARTER' },
            { label: 'Last Quarter', value: 'LAST_QUARTER' },
            { label: 'Next Quarter', value: 'NEXT_QUARTER' },
            { label: 'This Year', value: 'THIS_YEAR' },
            { label: 'Last Year', value: 'LAST_YEAR' }
        ];
    }

    /* =========================
       LOAD DATA
    ========================= */

    loadData() {

        searchIntakes({
            searchKey: '',
            pageNumber: this.pageNumber,
            pageSize: this.pageSize,
            selectedMonth: this.selectedMonth,
            dateFilter: this.selectedDateFilter
        })
        .then(result => {

            this.totalRecords = result.totalRecords;
            this.totalPages = result.totalPages;
            this.pageNumber = result.pageNumber;

            this.intakes = result.records.map(item => {

                let statusClass = 'status-default';
                let iconName = '';
                let iconClass = '';
                let showIcon = false;

                const status = (item.status || '').toLowerCase();

                if (status.includes('working')) {

                    statusClass = 'status-working';
                    iconName = 'utility:warning';
                    iconClass = 'icon-working';
                    showIcon = true;

                } else if (status.includes('converted')) {

                    statusClass = 'status-converted';
                    iconName = 'utility:success';
                    iconClass = 'icon-converted';
                    showIcon = true;

                } else if (
                    status.includes('retainer') ||
                    status.includes('signed')
                ) {

                    statusClass = 'status-retainer';
                    iconName = 'utility:file';
                    iconClass = 'icon-retainer';
                    showIcon = true;
                }

                return {
                    ...item,
                    statusClass,
                    iconName,
                    iconClass,
                    showIcon
                };
            });
        })
        .catch(error => {
            console.error('Load Data Error', error);
        });
    }

    loadAverage() {

        getAverageIntakeTime()
            .then(result => {
                this.formattedAverageTime = result;
            })
            .catch(error => {
                console.error('Average Error', error);
            });
    }

    /* =========================
       FILTER EVENTS
    ========================= */

    handleMonthChange(event) {

        this.selectedMonth = event.detail.value;
        this.pageNumber = 1;

        this.loadData();
    }

    handleDateFilterChange(event) {

        this.selectedDateFilter = event.detail.value;
        this.pageNumber = 1;

        this.loadData();
    }

    /* =========================
       PAGINATION
    ========================= */

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

    handlePageClick(event) {

        const page = Number(event.target.dataset.page);

        if (page !== this.pageNumber) {

            this.pageNumber = page;
            this.loadData();
        }
    }

    get pageNumbers() {

        const pages = [];

        let start = Math.max(1, this.pageNumber - 2);
        let end = Math.min(this.totalPages, this.pageNumber + 2);

        for (let i = start; i <= end; i++) {

            pages.push({
                label: i,
                value: i,
                className:
                    i === this.pageNumber
                        ? 'page-btn active'
                        : 'page-btn'
            });
        }

        return pages;
    }

    get disablePrevious() {
        return this.pageNumber <= 1;
    }

    get disableNext() {
        return this.pageNumber >= this.totalPages;
    }

    /* =========================
       OPEN RECORD
    ========================= */

    openRecord(event) {

        const recordId = event.currentTarget.dataset.id;

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