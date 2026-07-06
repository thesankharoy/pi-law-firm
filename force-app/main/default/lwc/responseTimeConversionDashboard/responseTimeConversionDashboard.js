import { LightningElement, wire, track } from 'lwc';

import getDashboardData
    from '@salesforce/apex/ResponseTimeConversionController.getDashboardData';

export default class ResponseTimeConversionDashboard extends LightningElement {

    @track buckets = [];
    @track insights = [];

    avgAnswerTime = 0;
    totalCalls = 0;
    conversionRate = 0;
    missedCallRate = 0;

    recommendation = '';

    isLoading = true;
    error;

    @wire(getDashboardData)
    wiredDashboard({ error, data }) {

        this.isLoading = false;

        if (data) {

            this.error = undefined;

            this.avgAnswerTime =
                this.formatNumber(
                    data.avgAnswerTime
                );

            this.totalCalls =
                data.totalCalls;

            this.conversionRate =
                this.formatPercent(
                    data.conversionRate
                );

            this.missedCallRate =
                this.formatPercent(
                    data.missedCallRate
                );

            this.recommendation =
                data.recommendation;

            this.insights =
                data.insights || [];

            this.buckets =
                (data.buckets || []).map(
                    row => {

                        let width =
                            Math.max(
                                3,
                                Math.round(
                                    row.conversionRate
                                )
                            );

                        let colorClass =
                            this.getColorClass(
                                row.conversionRate
                            );

                        return {

                            ...row,

                            conversionRate:
                                this.formatPercent(
                                    row.conversionRate
                                ),

                            totalCallPercent:
                                this.formatPercent(
                                    row.totalCallPercent
                                ),

                            barStyle:
                                `width:${width}%`,

                            barClass:
                                `progress-fill ${colorClass}`
                        };
                    }
                );

        }
        else if (error) {

            this.error = error;

            this.buckets = [];
            this.insights = [];

            console.error(
                'Dashboard Error',
                error
            );
        }
    }

    formatPercent(value) {

        if (
            value === null ||
            value === undefined
        ) {
            return '0.0';
        }

        return Number(value)
            .toFixed(1);
    }

    formatNumber(value) {

        if (
            value === null ||
            value === undefined
        ) {
            return 0;
        }

        return Number(value)
            .toFixed(0);
    }

    getColorClass(rate) {

        if (rate >= 40) {
            return 'green';
        }

        if (rate >= 25) {
            return 'yellow';
        }

        if (rate >= 10) {
            return 'orange';
        }

        return 'red';
    }

    get hasData() {

        return (
            this.buckets &&
            this.buckets.length > 0
        );
    }

    get currentProgressStyle() {

        let width =
            Math.min(
                100,
                this.conversionRate
            );

        return `width:${width}%`;
    }
}