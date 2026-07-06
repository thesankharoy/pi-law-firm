import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDrafts from '@salesforce/apex/FAQCurationController.getDrafts';
import approveEntry from '@salesforce/apex/FAQCurationController.approveEntry';
import retireEntry from '@salesforce/apex/FAQCurationController.retireEntry';
import updateResponse from '@salesforce/apex/FAQCurationController.updateResponse';

export default class FaqCuration extends LightningElement {
    wiredResult;
    rows;
    error;
    edits = {};

    @wire(getDrafts)
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
            metaLabel:
                (r.category || '') +
                (r.objectionType ? ' · ' + r.objectionType.replace(/_/g, ' ') : '') +
                ' · seen ' + r.frequency + ' · ' + r.successRate + '% signed'
        }));
    }

    handleChange(event) {
        this.edits[event.target.dataset.id] = event.target.value;
    }

    responseFor(id, fallback) {
        return this.edits[id] !== undefined ? this.edits[id] : fallback;
    }

    handleSave(event) {
        const id = event.currentTarget.dataset.id;
        const txt = this.edits[id];
        if (txt === undefined) {
            this.toast('Nothing changed', 'Edit the response first.', 'info');
            return;
        }
        updateResponse({ entryId: id, response: txt })
            .then(() => { this.toast('Saved', 'Response updated.', 'success'); return refreshApex(this.wiredResult); })
            .catch(() => this.toast('Error', 'Could not save.', 'error'));
    }

    handleApprove(event) {
        const id = event.currentTarget.dataset.id;
        const txt = this.edits[id];
        const chain = txt !== undefined ? updateResponse({ entryId: id, response: txt }) : Promise.resolve();
        chain
            .then(() => approveEntry({ entryId: id }))
            .then(() => { this.toast('Approved', 'Entry is now servable.', 'success'); return refreshApex(this.wiredResult); })
            .catch(() => this.toast('Error', 'Could not approve.', 'error'));
    }

    handleRetire(event) {
        const id = event.currentTarget.dataset.id;
        retireEntry({ entryId: id })
            .then(() => { this.toast('Retired', 'Entry retired.', 'success'); return refreshApex(this.wiredResult); })
            .catch(() => this.toast('Error', 'Could not retire.', 'error'));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}