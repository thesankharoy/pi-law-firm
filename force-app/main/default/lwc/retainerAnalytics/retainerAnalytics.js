import { LightningElement, wire } from 'lwc';
import getAnalytics from '@salesforce/apex/RetainerAnalyticsController.getAnalytics';

import CHARTJS from '@salesforce/resourceUrl/chartjs';
import { loadScript } from 'lightning/platformResourceLoader';

export default class RetainerFunnelChart extends LightningElement {

    chart;
    chartJsLoaded = false;
    dataLoaded = false;

    sentCount = 0;
    openCount = 0;
    signedCount = 0;

    @wire(getAnalytics)
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

    renderedCallback() {
        if (this.chartJsLoaded) return;

        this.chartJsLoaded = true;

        loadScript(this, CHARTJS)
            .then(() => {
                this.drawChart();
            })
            .catch(error => {
                console.error(error);
            });
    }

    drawChart() {

        // ❗ wait until BOTH conditions are true
        if (!this.chartJsLoaded || !this.dataLoaded) {
            return;
        }

        const canvas = this.template.querySelector('canvas.funnelChart');

        if (!canvas) return;

        const ctx = canvas.getContext('2d');

        if (this.chart) {
            this.chart.destroy();
        }

        this.chart = new window.Chart(ctx, {
            type: 'bar',
            data: {
                labels: ['Retainer Sent', 'View', 'Retainer Signed'],
                datasets: [{
                    data: [
                        Number(this.sentCount),
                        Number(this.openCount),
                        Number(this.signedCount)
                    ],
                    backgroundColor: [
                        '#00E5FF', // Neon Cyan
                        '#FFD600', // Bright Yellow
                        '#00FF85'  // Neon Green
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
                plugins: {
                    legend: { display: false }
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