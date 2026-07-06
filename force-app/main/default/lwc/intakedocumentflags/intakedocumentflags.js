import { LightningElement, api, track, wire } from 'lwc';
import { getRecord }             from 'lightning/uiRecordApi';
import getDocumentFlags          from '@salesforce/apex/DocumentFlagsController.getDocumentFlags';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';

const INTAKE_FIELDS = ['Intake__c.Status__c', 'Intake__c.Incident_Type__c'];

const PRIORITY_META = {
    HIGH:   { label: 'HIGH', cssClass: 'badge badge--high' },
    MEDIUM: { label: 'MED',  cssClass: 'badge badge--medium' },
    LOW:    { label: 'LOW',  cssClass: 'badge badge--low' }
};

export default class IntakeDocumentFlags extends LightningElement {
    @api recordId;

    @track _result      = null;
    @track _loading     = true;
    @track _error       = null;
    @track _showPresent = false;

    // Watch record changes so gauge refreshes when a doc is uploaded
    @wire(getRecord, { recordId: '$recordId', fields: INTAKE_FIELDS })
    wiredRecord({ data, error }) {
        if (data || error) {
            this._loadFlags();
        }
    }

    connectedCallback() {
        this._loadFlags();
    }

    async _loadFlags() {
        this._loading = true;
        this._error   = null;
        try {
            const raw       = await getDocumentFlags({ intakeId: this.recordId });
            this._result    = this._decorate(raw);
        } catch (e) {
            this._error = e.body?.message || e.message || 'Unknown error loading document flags.';
        } finally {
            this._loading = false;
        }
    }

    _decorate(raw) {
        if (!raw) return null;
        const pct = raw.totalReq > 0
            ? Math.round((raw.totalDone / raw.totalReq) * 100) : 0;
        return {
            ...raw,
            missing:        (raw.missing || []).map(f => this._decorateFlag(f)),
            present:        (raw.present || []).map(f => this._decorateFlag(f)),
            completionPct:  pct,
            gaugeStyle:     `width: ${Math.min(pct, 100)}%`,
            gaugeClass:     pct >= 80 ? 'gauge__fill gauge__fill--good'
                          : pct >= 40 ? 'gauge__fill gauge__fill--warn'
                          :             'gauge__fill gauge__fill--bad'
        };
    }

    _decorateFlag(f) {
        const meta = PRIORITY_META[f.priority] || PRIORITY_META.LOW;
        return {
            ...f,
            badgeClass:    meta.cssClass,
            badgeLabel:    meta.label,
            uploadedLabel: f.uploadedAt ? 'Uploaded ' + this._fmtDate(f.uploadedAt) : null
        };
    }

    _fmtDate(iso) {
        try {
            const [y, m, d] = iso.split('-');
            const months = ['Jan','Feb','Mar','Apr','May','Jun',
                            'Jul','Aug','Sep','Oct','Nov','Dec'];
            return `${months[parseInt(m,10)-1]} ${parseInt(d,10)}, ${y}`;
        } catch(e) { return iso; }
    }

    handleRefresh() {
        getRecordNotifyChange([{ recordId: this.recordId }]);
        this._loadFlags();
    }

    handleTogglePresent() {
        this._showPresent = !this._showPresent;
    }

    get isLoading()    { return this._loading; }
    get hasError()     { return !!this._error; }
    get errorMessage() { return this._error; }
    get result()       { return this._result; }
    get showPresent()  { return this._showPresent; }
    get hasMissing()   { return (this._result?.missing || []).length > 0; }
    get allClear()     { return this._result && !this.hasMissing; }

    get highCount() {
        return (this._result?.missing || []).filter(f => f.priority === 'HIGH').length;
    }

    get missingCount() {
        return (this._result?.missing || []).length;
    }

    get presentCount() {
        return (this._result?.present || []).length;
    }

    get toggleLabel() {
        const n = this.presentCount;
        return this._showPresent
            ? `Hide ${n} filed document${n !== 1 ? 's' : ''}`
            : `Show ${n} filed document${n !== 1 ? 's' : ''}`;
    }

    get statusSummary() {
        if (!this._result) return '';
        const { totalDone, totalReq, completionPct } = this._result;
        return `${totalDone} of ${totalReq} required documents on file (${completionPct}% complete)`;
    }
}