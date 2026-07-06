import { LightningElement, wire } from 'lwc';
import getLossSummary from '@salesforce/apex/WinLossDashboardController.getLossSummary';

export default class WhyWeLoseCard extends LightningElement {
    summary;
    error;

    @wire(getLossSummary, { lookbackDays: 90 })
    wired({ data, error }) {
        if (data) {
            this.summary = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.summary = undefined;
        }
    }

    get loading() {
        return !this.summary && !this.error;
    }
    get hasData() {
        return this.summary && this.summary.total > 0;
    }
    get total() {
        return this.summary ? this.summary.total : 0;
    }
    get processPct() {
        return (this.summary ? this.summary.processPct : 0) + '%';
    }
    get processCount() {
        return this.summary ? this.summary.processCount : 0;
    }
    get lookbackDays() {
        return this.summary ? this.summary.lookbackDays : 0;
    }

    get faultRows() {
        if (!this.summary) return [];
        return this.summary.faults.map((f) => ({
            ...f,
            barStyle: 'width:' + f.pct + '%',
            countLabel: f.count + ' (' + f.pct + '%)'
        }));
    }
    get reasonRows() {
        return this.summary ? this.summary.reasons : [];
    }
    get objectionRows() {
        return this.summary ? this.summary.objections : [];
    }
}