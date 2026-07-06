import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = ['Intake__c.AI_Recommended_Action__c'];

const PRIORITY_META = {
    HIGH: { label: 'HIGH', badgeClass: 'badge badge-high', rank: 0 },
    MED:  { label: 'MED',  badgeClass: 'badge badge-med',  rank: 1 },
    LOW:  { label: 'LOW',  badgeClass: 'badge badge-low',  rank: 2 }
};

export default class AiRecommendedActions extends LightningElement {

    @api recordId;

    actions = [];
    isLoading = true;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            const raw = data.fields.AI_Recommended_Action__c.value || '';
            this.actions = this.parseActions(raw);
            this.isLoading = false;
        }
        if (error) {
            console.error('AI Recommended Actions Error', error);
            this.isLoading = false;
        }
    }

    parseActions(text) {
        const parts = text.split('## ').filter((p) => p.trim());

        let items = parts.map((part) => {
            const lines = part.split('\n');
            let title = lines[0].trim();
            const description = lines.slice(1).join('\n').trim();

            let priority;
            const m = title.match(/^\[?\s*(HIGH|MED|MEDIUM|LOW)\s*\]?\s*[:\-–|]?\s*/i);
            if (m) {
                priority = m[1].toUpperCase().startsWith('MED') ? 'MED' : m[1].toUpperCase();
                title = title.slice(m[0].length).trim();
            } else {
                priority = this.derivePriority(title, description);
            }

            const meta = PRIORITY_META[priority] || PRIORITY_META.LOW;
            return {
                id: title,
                priority: meta.label,
                rank: meta.rank,
                badgeClass: meta.badgeClass,
                title,
                description,
                expanded: false,
                chevron: 'utility:down'
            };
        });

        if (!items.length) {
            return [{
                id: 'none', index: 0, priority: 'LOW', rank: 2,
                badgeClass: 'badge badge-low',
                title: 'No Recommendations',
                description: 'No AI recommendations available.',
                expanded: true, chevron: 'utility:up'
            }];
        }

        // HIGH → MED → LOW (stable within a priority)
        items.sort((a, b) => a.rank - b.rank);

        // assign index + expand the first action by default
        items = items.map((it, idx) => ({
            ...it,
            index: idx,
            expanded: idx === 0,
            chevron: idx === 0 ? 'utility:up' : 'utility:down'
        }));

        return items;
    }

    derivePriority(title, desc) {
        const t = `${title} ${desc}`.toLowerCase();
        if (/(immediate|urgent|today|asap|critical|now)/.test(t)) return 'HIGH';
        if (/(verify|send|schedule|confirm|retainer|obtain|review)/.test(t)) return 'MED';
        return 'LOW';
    }

    handleToggle(event) {
        const i = Number(event.currentTarget.dataset.index);
        this.actions = this.actions.map((a) => {
            if (a.index !== i) return a;
            const expanded = !a.expanded;
            return { ...a, expanded, chevron: expanded ? 'utility:up' : 'utility:down' };
        });
    }

    get actionCount() {
        const n = this.actions.length;
        return `${n} action${n === 1 ? '' : 's'}`;
    }
}