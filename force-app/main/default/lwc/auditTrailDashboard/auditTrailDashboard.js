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
        label: 'Field',
        fieldName: 'fieldName'
    },

    {
        label: 'Old Value',
        fieldName: 'oldValue'
    },

    {
        label: 'New Value',
        fieldName: 'newValue'
    },

    {
        label: 'Changed On',
        fieldName: 'changeDate',
        type: 'date'
    }
];

export default class AuditTrailDashboard
extends LightningElement {

    columns = COLUMNS;

    allRecords = [];
    auditRecords = [];

    pageSize = 10;
    pageNumber = 1;

    statusChanges = 0;
    ownerChanges = 0;
    sourceChanges = 0;
    totalEvents = 0;

    @wire(getAuditSummary)
    wiredSummary({ data, error }) {

        if (data) {

            this.statusChanges =
                data.statusChanges;

            this.ownerChanges =
                data.ownerChanges;

            this.sourceChanges =
                data.sourceChanges;

            this.totalEvents =
                data.totalEvents;
        }
        else if (error) {

            console.error(error);
        }
    }

    @wire(getRecentAuditRecords)
    wiredAudit({ data, error }) {

        if (data) {

            this.allRecords = data;

            this.updatePage();
        }
        else if (error) {

            console.error(error);
        }
    }

    updatePage() {

        const start =
            (this.pageNumber - 1)
            * this.pageSize;

        const end =
            start + this.pageSize;

        this.auditRecords =
            this.allRecords.slice(
                start,
                end
            );
    }

    handleNext() {

        if (this.pageNumber <
            this.totalPages) {

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

    get totalPages() {

        return Math.ceil(
            this.allRecords.length /
            this.pageSize
        );
    }

    get disablePrevious() {

        return this.pageNumber === 1;
    }

    get disableNext() {

        return this.pageNumber ===
            this.totalPages;
    }
}