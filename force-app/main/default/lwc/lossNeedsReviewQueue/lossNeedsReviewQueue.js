import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getNeedsReview from '@salesforce/apex/WinLossDashboardController.getNeedsReview';
import markReviewed from '@salesforce/apex/WinLossDashboardController.markReviewed';

export default class LossNeedsReviewQueue extends NavigationMixin(LightningElement) {
    wiredResult;
    rows;
    error;

    @wire(getNeedsReview)
    wired(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.rows = undefined;
        }
    }

    get loading() {
        return !this.rows && !this.error;
    }
    get hasRows() {
        return this.rows && this.rows.length > 0;
    }
    get count() {
        return this.rows ? this.rows.length : 0;
    }
    get displayRows() {
        if (!this.rows) return [];
        return this.rows.map((r) => ({
            ...r,
            confidenceLabel:
                r.confidence === null || r.confidence === undefined
                    ? 'n/a'
                    : Math.round(r.confidence * 100) + '%'
        }));
    }

    handleOpen(event) {
        const intakeId = event.currentTarget.dataset.id;
        if (!intakeId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: intakeId, objectApiName: 'Intake__c', actionName: 'view' }
        });
    }

    handleConfirm(event) {
        const id = event.currentTarget.dataset.id;
        markReviewed({ analysisId: id })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Confirmed', message: 'Classification accepted.', variant: 'success' })
                );
                return refreshApex(this.wiredResult);
            })
            .catch(() => {
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Error', message: 'Could not update the record.', variant: 'error' })
                );
            });
    }
}