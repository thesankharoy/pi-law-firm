import { LightningElement, wire } from 'lwc';
import getSpecialistRisk from '@salesforce/apex/SpecialistRiskController.getSpecialistRisk';

export default class SpecialistRiskDashboard extends LightningElement {
    windowDays = 30;
    rows;
    error;

    @wire(getSpecialistRisk, { windowDays: '$windowDays' })
    wired({ data, error }) {
        if (data) {
            this.rows = data.map(r => {
                return {
                    ...r,
                    riskDotClass:
                        r.riskLevel === 'At Risk'
                            ? 'dot risk-at'
                            : r.riskLevel === 'Watch'
                            ? 'dot risk-watch'
                            : 'dot risk-healthy'
                };
            });

            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.rows = undefined;
        }
    }

    get isLoading() {
        return !this.rows && !this.error;
    }

    get isEmpty() {
        return this.rows && this.rows.length === 0;
    }

    get errorMsg() {
        if (!this.error) return null;
        return (
            (this.error.body && this.error.body.message) ||
            'Could not load data.'
        );
    }

    get totalSpecialists() {
        return this.rows ? this.rows.length : 0;
    }

    get healthyCount() {
        return this.rows
            ? this.rows.filter(r => r.riskLevel === 'Healthy').length
            : 0;
    }

    get watchCount() {
        return this.rows
            ? this.rows.filter(r => r.riskLevel === 'Watch').length
            : 0;
    }

    get riskCount() {
        return this.rows
            ? this.rows.filter(r => r.riskLevel === 'At Risk').length
            : 0;
    }

    get overallRiskScore() {
        if (!this.rows || this.rows.length === 0) {
            return 0;
        }

        let score = 0;

        this.rows.forEach(r => {
            if (r.riskLevel === 'At Risk') {
                score += 100;
            } else if (r.riskLevel === 'Watch') {
                score += 50;
            }
        });

        return Math.round(score / this.rows.length);
    }

    get progressStyle() {
        return `width:${this.overallRiskScore}%`;
    }
}