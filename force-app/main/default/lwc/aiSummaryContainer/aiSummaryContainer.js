import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Intake__c.AI_Summary__c',
    'Intake__c.Qualification_Score__c'
];

const POSITIVE = ['available', 'strong', 'high', 'clear', 'identified', 'confirmed', 'severe', 'good'];
const NEGATIVE = ['risk', 'delay', 'hold', 'old', 'required', 'urgent', 'unknown', 'low', 'missing', 'poses', 'no '];

export default class AiSummaryContainer extends LightningElement {

    @api recordId;

    fullText = '';
    confidence = 0;
    isLoading = true;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ error, data }) {
        if (data) {
            this.fullText = data.fields.AI_Summary__c.value || 'No AI summary available.';
            this.confidence = data.fields.Qualification_Score__c.value || 0;
            this.isLoading = false;
        }
        if (error) {
            console.error('AI Summary Error', JSON.stringify(error));
            this.isLoading = false;
        }
    }

    get leadTemperature() {
        if (this.confidence >= 75) return 'Hot Lead';
        if (this.confidence >= 45) return 'Warm Lead';
        return 'Cold Lead';
    }

    get tempChipClass() {
        if (this.confidence >= 75) return 'chip chip-hot';
        if (this.confidence >= 45) return 'chip chip-warm';
        return 'chip chip-cold';
    }

    get conversionLikelihood() {
        if (this.confidence >= 80) return 'High conversion likelihood';
        if (this.confidence >= 55) return 'Medium-High conversion likelihood';
        if (this.confidence >= 40) return 'Medium conversion likelihood';
        if (this.confidence >= 20) return 'Low-Medium conversion likelihood';
        return 'Low conversion likelihood';
    }

    get gaugeStyle() {
        return `stroke-dasharray: ${this.confidence} 100`;
    }

    get gaugeArcClass() {
        if (this.confidence >= 70) return 'gauge-arc arc-green';
        if (this.confidence >= 40) return 'gauge-arc arc-blue';
        return 'gauge-arc arc-red';
    }

    get showLiability() {
        const t = this.fullText.toLowerCase();
        return t.includes('liability') &&
            (t.includes('high') || t.includes('clear fault') || t.includes('strong'));
    }

    get insights() {
        if (!this.fullText) return [];
        return this.fullText
            .split('\n')
            .map((l) => l.replace(/^[-•\s]+/, '').trim())
            .filter((l) => l.length)
            .map((text, i) => ({
                id: i,
                text,
                dotClass: `dot ${this.sentimentClass(text)}`
            }));
    }

    sentimentClass(text) {
        const t = text.toLowerCase();
        if (POSITIVE.some((w) => t.includes(w))) return 'dot-green';
        if (NEGATIVE.some((w) => t.includes(w))) return 'dot-red';
        return 'dot-amber';
    }
}