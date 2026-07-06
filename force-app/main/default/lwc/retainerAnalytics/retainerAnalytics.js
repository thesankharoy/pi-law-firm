import { LightningElement, wire } from 'lwc';
import getAnalytics from '@salesforce/apex/RetainerAnalyticsController.getAnalytics';

import CHARTJS from '@salesforce/resourceUrl/chartjs';
import { loadScript } from 'lightning/platformResourceLoader';

export default class RetainerFunnelChart extends LightningElement {

    chart;

    chartJsLoaded = false;
    chartJsLoading = false;
    dataLoaded = false;
    selectedFilter = 'THIS_MONTH';

    sentCount = 0;
    openCount = 0;
    signedCount = 0;

    @wire(getAnalytics, { filterType: '$selectedFilter' })
wiredData({ data, error }) {

    if (data) {

        this.sentCount = data.sentCount || 0;
        this.openCount = data.openCount || 0;
        this.signedCount = data.signedCount || 0;

        this.dataLoaded = true;

        this.drawChart();

    } else if (error) {
        console.error(error);
    }
}

    get filterOptions() {
    return [
        { label: 'Today', value: 'TODAY' },
        { label: 'Yesterday', value: 'YESTERDAY' },
        { label: 'Last 7 Days', value: 'LAST_7_DAYS' },
        { label: 'This Month', value: 'THIS_MONTH' },
        { label: 'Last Month', value: 'LAST_MONTH' },
        { label: 'This Year', value: 'THIS_YEAR' },
        { label: 'All Time', value: 'ALL' }
    ];
 }

        handleFilterChange(event) {
            this.selectedFilter = event.detail.value;

            // We'll call Apex here later
            console.log('Selected Filter:', this.selectedFilter);
        }

    renderedCallback() {

        if (this.chartJsLoaded || this.chartJsLoading) {
            return;
        }

        this.chartJsLoading = true;

        loadScript(this, CHARTJS)
            .then(() => {

                console.log('Chart.js Loaded');
                console.log('window.Chart =>', window.Chart);

                this.chartJsLoaded = true;
                this.chartJsLoading = false;

                this.drawChart();
            })
            .catch(error => {

                this.chartJsLoading = false;

                console.error(
                    'Chart.js Load Error:',
                    error
                );
            });
    }

    drawChart() {

        if (!this.chartJsLoaded || !this.dataLoaded) {
            return;
        }

        if (!window.Chart) {

            console.error(
                'Chart.js not available on window object'
            );

            return;
        }

        const canvas =
            this.template.querySelector(
                'canvas.funnelChart'
            );

        if (!canvas) {
            return;
        }

        const ctx = canvas.getContext('2d');

        if (this.chart) {
            this.chart.destroy();
        }

        this.chart = new window.Chart(ctx, {

            type: 'bar',

            data: {

                labels: [
                    'Retainer Sent',
                    'View',
                    'Retainer Signed'
                ],

                datasets: [{

                    data: [
                        Number(this.sentCount),
                        Number(this.openCount),
                        Number(this.signedCount)
                    ],

                    backgroundColor: [
                        '#00E5FF',
                        '#FFD600',
                        '#00FF85'
                    ],

                    borderColor: [
                        '#00E5FF',
                        '#FFD600',
                        '#00FF85'
                    ],

                    borderWidth: 2,
                    borderRadius: 8,
                    barThickness: 40
                }]
            },

            options: {

                indexAxis: 'y',

                responsive: true,

                maintainAspectRatio: false,

                plugins: {

                    legend: {
                        display: false
                    }
                },

                scales: {

                    x: {
                        beginAtZero: true
                    }
                }
            }
        });
    }
}