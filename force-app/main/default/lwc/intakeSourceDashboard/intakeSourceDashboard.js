import { LightningElement, wire } from 'lwc';
import getSourcePerformance from '@salesforce/apex/IntakeSourceDashboardController.getSourcePerformance';

export default class IntakeSourceDashboard extends LightningElement {

    data = [];
    error;
    topSource = '';

    @wire(getSourcePerformance)
    wiredResult({ error, data }) {

        if (data) {

            // Find source with highest total intakes
            const top = data.reduce((max, item) =>
                item.totalIntakes > max.totalIntakes ? item : max
            );

            this.topSource = top.source;

            // Add CSS class to each card
            this.data = data.map(item => ({
                ...item,
                cardClass:
                    item.source === this.topSource
                        ? 'source-card active'
                        : 'source-card'
            }));

            this.error = undefined;

        } else if (error) {

            this.error = error;
            this.data = [];
        }
    }
    get cards() {
    if (!this.data || this.data.length === 0) {
        return [];
    }
    // total across all sources
    const grandTotal = this.data.reduce(
        (sum, item) => sum + (item.totalIntakes || 0),
        0
    );
    return this.data.map(item => {
        const val = item.totalIntakes || 0;
        const pct = grandTotal > 0
            ? ((val / grandTotal) * 100).toFixed(1)
            : '0.0';
        return {
            ...item,
            percentage: pct   // e.g. "63.3"
        };
    });
}
    get chartData() {
    if (!this.data || this.data.length === 0) {
        return [];
    }
    const max = this.data.reduce(
        (m, item) => Math.max(m, item.totalIntakes || 0),
        0
    );
    return this.data.map(item => {
        const val = item.totalIntakes || 0;
        let width = max > 0 ? (val / max) * 100 : 0;
        if (width > 0 && width < 4) {
            width = 4; // keep small values visible
        }
        return {
            source: item.source,
            totalIntakes: val,
            barStyle: `width:${width}%;`
        };
    });
}
}