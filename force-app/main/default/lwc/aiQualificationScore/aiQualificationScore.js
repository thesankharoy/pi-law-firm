import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import QUALIFICATION_SCORE_FIELD from '@salesforce/schema/Intake__c.Qualification_Score__c';
import AI_SENTIMENT_FIELD       from '@salesforce/schema/Intake__c.AI_Sentiment__c';
import LAST_MODIFIED_FIELD      from '@salesforce/schema/Intake__c.LastModifiedDate';

const FIELDS = [QUALIFICATION_SCORE_FIELD, AI_SENTIMENT_FIELD, LAST_MODIFIED_FIELD];

export default class AiQualificationScore extends LightningElement {
    @api recordId;

    @track _animatedScore = 0;
    @track _animatedWidth = 0;
    _animationFrame;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    intake({ data, error }) {
        if (data) {
            const raw = getFieldValue(data, QUALIFICATION_SCORE_FIELD) || 0;
            this._targetScore = Math.min(Math.max(Math.round(raw), 0), 100);
            this._sentiment   = getFieldValue(data, AI_SENTIMENT_FIELD) || '';
            this._lastMod     = getFieldValue(data, LAST_MODIFIED_FIELD);
            this._startAnimation();
        }
    }

    /* ── computed getters ── */

    get score()          { return this._animatedScore; }
    get updatedLabel()   { return this._relativeTime(this._lastMod); }

    get progressStyle() {
        return `width:${this._animatedWidth}%; background:${this._barColor}; transition:none;`;
    }

    get scoreStyle() {
        return `color:${this._scoreColor};`;
    }

    get _barColor() {
        if (this._targetScore >= 70) return '#22c55e';   /* green  */
        if (this._targetScore >= 40) return '#e6a817';   /* amber  */
        return '#ef4444';                                 /* red    */
    }

    get _scoreColor() { return this._barColor; }

    /* conversion label */
    get conversionLabel() {
        const s = this._targetScore;
        if (s >= 80) return 'High Conversion';
        if (s >= 55) return 'Med-High Conversion';
        if (s >= 35) return 'Med Conversion';
        return 'Low Conversion';
    }

    /* liability label driven by AI_Sentiment */
    get liabilityLabel() {
        const sent = (this._sentiment || '').toLowerCase();
        if (sent.includes('high')) return 'High Liability';
        if (sent.includes('low'))  return 'Low Liability';
        return 'Med Liability';
    }

    get hasConversionTag() { return !!this._targetScore; }
    get hasLiabilityTag()  { return !!this._sentiment; }

    /* ── animation ── */

    _startAnimation() {
        cancelAnimationFrame(this._animationFrame);
        const target = this._targetScore;
        const duration = 900;
        const start = performance.now();

        const step = (now) => {
            const t = Math.min((now - start) / duration, 1);
            const eased = 1 - Math.pow(1 - t, 3);   /* ease-out cubic */
            this._animatedScore = Math.round(eased * target);
            this._animatedWidth = parseFloat((eased * target).toFixed(1));

            if (t < 1) {
                this._animationFrame = requestAnimationFrame(step);
            }
        };
        this._animationFrame = requestAnimationFrame(step);
    }

    disconnectedCallback() {
        cancelAnimationFrame(this._animationFrame);
    }

    /* ── helpers ── */

    _relativeTime(isoString) {
        if (!isoString) return '';
        const diff = Date.now() - new Date(isoString).getTime();
        const mins  = Math.floor(diff / 60000);
        if (mins < 1)  return 'Updated just now';
        if (mins < 60) return `Updated ${mins}m ago`;
        const hrs = Math.floor(mins / 60);
        return `Updated ${hrs}h ago`;
    }
}