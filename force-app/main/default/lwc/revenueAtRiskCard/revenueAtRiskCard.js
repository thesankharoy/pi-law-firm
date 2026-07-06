import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getOpenLeaks from '@salesforce/apex/RevenueLeakDashboardController.getOpenLeaks';

export default class RevenueAtRiskCard extends NavigationMixin(LightningElement) {
    summary;
    error;

    @wire(getOpenLeaks)
    wiredLeaks({ data, error }) {
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

    get hasLeaks() {
        return this.summary && this.summary.rows && this.summary.rows.length > 0;
    }

    get totalAtRisk() {
        return this.formatCurrency(this.summary ? this.summary.totalAtRisk : 0);
    }

    get openCount() {
        return this.summary ? this.summary.openCount : 0;
    }

    get criticalCount() {
        return this.summary ? this.summary.criticalCount : 0;
    }

    get displayRows() {
        if (!this.summary) {
            return [];
        }
        return this.summary.rows.map((r) => ({
            ...r,
            amountFmt: this.formatCurrency(r.amount),
            overdueLabel: r.daysOverdue + (r.daysOverdue === 1 ? ' day overdue' : ' days overdue'),
            badgeClass:
                'slds-badge slds-m-right_small ' +
                (r.severity === 'Critical'
                    ? 'slds-theme_error'
                    : r.severity === 'High'
                    ? 'slds-theme_warning'
                    : '')
        }));
    }

    formatCurrency(n) {
        return '$' + Math.round(n || 0).toLocaleString('en-US');
    }

    handleOpen(event) {
        const intakeId = event.currentTarget.dataset.id;
        if (!intakeId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: intakeId,
                objectApiName: 'Intake__c',
                actionName: 'view'
            }
        });
    }
}