import { LightningElement, wire } from 'lwc';
import getSourcePerformance from '@salesforce/apex/IntakeSourceDashboardController.getSourcePerformance';

export default class IntakeSourceDashboard extends LightningElement {

    data;
    error;
    topSource = '';

    @wire(getSourcePerformance)
    wiredResult({ error, data }) {
        if (data) {
            this.data = data;

            // find top source
            let top = data.reduce((max, item) =>
                item.totalIntakes > max.totalIntakes ? item : max
            );

            this.topSource = top.source;

            this.error = undefined;

            // trigger animation after render
            setTimeout(() => {
                this.highlightTopCard();
            }, 300);

        } else if (error) {
            this.error = error;
            this.data = undefined;
        }
    }

    highlightTopCard() {
        const cards = this.template.querySelectorAll('.source-card');

        cards.forEach(card => {
            if (card.dataset.source === this.topSource) {
                card.classList.add('top-glow');
            }
        });
    }
}