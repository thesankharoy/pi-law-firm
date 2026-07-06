import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Intake__c.Follow_Up_Notes__c',
    'Intake__c.Objection_Raised__c',
    'Intake__c.Follow_Up_Next_Step__c',
    'Intake__c.LastModifiedDate'
];

const EMPHASIS_RE = /(Recommended wording:|Suggested response:|Suggested wording:|Recommended response:|Action:)/i;

export default class CallInsights extends LightningElement {

    @api recordId;

    fullNotes      = '';
    fullObjections = '';
    fullNextSteps  = '';

    isLoading   = true;
    isEmpty     = false;
    lastUpdated = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.fullNotes      = data.fields.Follow_Up_Notes__c.value     || '';
            this.fullObjections = data.fields.Objection_Raised__c.value    || '';
            this.fullNextSteps  = data.fields.Follow_Up_Next_Step__c.value || '';

            const modified = data.fields.LastModifiedDate.value;
            this.lastUpdated = modified ? new Date(modified).toLocaleString() : '';

            this.isLoading = false;
            this.isEmpty = !this.fullNotes && !this.fullObjections && !this.fullNextSteps;
        }
        if (error) {
            console.error('Call Insights Error', JSON.stringify(error));
            this.isLoading = false;
            this.isEmpty = true;
        }
    }

    get notesParagraphs() {
        return this._toParagraphs(this.fullNotes);
    }

    get hasObjections() {
        const t = (this.fullObjections || '').trim().toLowerCase().replace(/^[-•—\s]+/, '');
        return !!t && !t.startsWith('none');
    }

    get objectionItems() {
        return this._toParagraphs(this.fullObjections);
    }

    get nextSteps() {
        return (this.fullNextSteps || '')
            .split('\n')
            .map((l) => l.replace(/^[-•\s]+/, '').trim())
            .filter(Boolean)
            .map((text, i) => {
                const m = text.match(EMPHASIS_RE);
                let main = text;
                let emphasis = '';
                if (m) {
                    main = text.slice(0, m.index).trim();
                    emphasis = text.slice(m.index).trim();
                }
                return { id: `step-${i}`, main, emphasis };
            });
    }

    _toParagraphs(text) {
        return (text || '')
            .split(/\n+/)
            .map((l) => l.replace(/^[-•\s]+/, '').trim())
            .filter(Boolean)
            .map((t, i) => ({ id: `p-${i}`, text: t }));
    }
}