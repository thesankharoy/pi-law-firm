import { LightningElement, wire } from 'lwc';

import getAuditSummary
from '@salesforce/apex/IntakeAuditController.getAuditSummary';

import getRecentAuditRecords
from '@salesforce/apex/IntakeAuditController.getRecentAuditRecords';

const COLUMNS = [

    {
        label: 'User',
        fieldName: 'userName'
    },

    {
        label: 'Field Changed',
        fieldName: 'fieldName'
    },

    {
        label: 'Old Value',
        fieldName: 'oldValue',
        cellAttributes: {
            class: {
                fieldName: 'oldValueClass'
            }
        }
    },

    {
        label: 'New Value',
        fieldName: 'newValue',
        cellAttributes: {
            class: {
                fieldName: 'newValueClass'
            }
        }
    },

    {
        label: 'Changed On',
        fieldName: 'changeDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    }
];

export default class AuditTrailDashboard extends LightningElement {

    columns = COLUMNS;

    allRecords = [];
    auditRecords = [];

    pageSize = 10;
    pageNumber = 1;

    statusChanges = 0;
    ownerChanges = 0;
    sourceChanges = 0;
    totalEvents = 0;

    /* =========================================
       SUMMARY
    ========================================= */

    @wire(getAuditSummary)
    wiredSummary({ data, error }) {

        if (data) {

            this.statusChanges = data.statusChanges;
            this.ownerChanges = data.ownerChanges;
            this.sourceChanges = data.sourceChanges;
            this.totalEvents = data.totalEvents;

        } else if (error) {

            console.error('Summary Error:', error);
        }
    }

    /* =========================================
       AUDIT RECORDS
    ========================================= */

    @wire(getRecentAuditRecords)
    wiredAudit({ data, error }) {

        if (data) {

            this.allRecords = data.map(record => {

                return {
                    ...record,

                    oldValueClass:
                        'slds-text-color_warning slds-text-title_bold',

                    newValueClass:
                        'slds-text-color_success slds-text-title_bold'
                };
            });

            this.updatePage();

        } else if (error) {

            console.error('Audit Error:', error);
        }
    }

    /* =========================================
       PAGINATION
    ========================================= */

    updatePage() {

        const start =
            (this.pageNumber - 1) * this.pageSize;

        const end =
            start + this.pageSize;

        this.auditRecords =
            this.allRecords.slice(start, end);
    }

    handleNext() {

        if (this.pageNumber < this.totalPages) {

            this.pageNumber++;
            this.updatePage();
        }
    }

    handlePrevious() {

        if (this.pageNumber > 1) {

            this.pageNumber--;
            this.updatePage();
        }
    }

    /* =========================================
       GETTERS
    ========================================= */

    get totalPages() {

        return Math.ceil(
            this.allRecords.length / this.pageSize
        );
    }

    get disablePrevious() {

        return this.pageNumber === 1;
    }

    get disableNext() {

        return this.pageNumber >= this.totalPages;
    }
}