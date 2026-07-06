import { LightningElement } from 'lwc';

export default class TokenUsageCalculator extends LightningElement {
    // --- A typical month at your firm (slider inputs) ---
    leads = 200;   // new leads worked / month
    calls = 8;     // call attempts per lead
    mins = 2;      // average minutes per call
    trans = 35;    // % of calls transcribed
    texts = 18;    // text messages per lead
    ai = 100;      // % of leads we run AI on
    store = 50;    // GB stored in S3
    sign = 15;     // % of leads that become signed cases

    // --- Price assumptions (number inputs) ---
    rSms = 0.012;   // $ per text (incl. carrier)
    rVoice = 0.014; // $ per call minute
    nNum = 3;       // phone numbers in use
    rNum = 1.15;    // $ per phone number / month
    rAi = 0.20;     // $ per intake (Claude)
    rDg = 0.0077;   // $ per minute (Deepgram)
    rS3 = 0.023;    // $ per GB / month (S3)

    // Single handler for every slider and number input.
    // The field name is carried on each input via data-field.
    handleInput(event) {
        const field = event.target.dataset.field;
        if (field) {
            this[field] = parseFloat(event.target.value) || 0;
        }
    }

    // ---------- core calculation (mirrors the original calc()) ----------
    get callMins() {
        return this.leads * this.calls * this.mins;
    }
    get twilio() {
        return this.callMins * this.rVoice + this.leads * this.texts * this.rSms + this.nNum * this.rNum;
    }
    get claude() {
        return this.leads * (this.ai / 100) * this.rAi;
    }
    get deepgram() {
        return this.callMins * (this.trans / 100) * this.rDg;
    }
    get s3() {
        return this.store * this.rS3;
    }
    get total() {
        return this.twilio + this.claude + this.deepgram + this.s3;
    }
    get perLead() {
        return this.leads > 0 ? this.total / this.leads : 0;
    }
    get signed() {
        return this.leads * (this.sign / 100);
    }
    get perCase() {
        return this.signed > 0 ? this.total / this.signed : 0;
    }

    // ---------- formatting ----------
    money(x) {
        if (x >= 100) {
            return '$' + x.toLocaleString('en-US', { maximumFractionDigits: 0 });
        }
        return '$' + x.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }

    // ---------- display getters (templates can't call methods with args) ----------
    get leadsDisplay() {
        return this.leads.toLocaleString('en-US');
    }
    get leadsDay() {
        return Math.max(1, Math.round(this.leads / 22));
    }
    get storeDisplay() {
        return this.store.toLocaleString('en-US');
    }
    get twilioDisplay() {
        return this.money(this.twilio);
    }
    get claudeDisplay() {
        return this.money(this.claude);
    }
    get deepgramDisplay() {
        return this.money(this.deepgram);
    }
    get s3Display() {
        return this.money(this.s3);
    }
    get totalDisplay() {
        return this.money(this.total);
    }
    get perLeadDisplay() {
        return this.money(this.perLead);
    }
    get perCaseDisplay() {
        return this.money(this.perCase);
    }
}