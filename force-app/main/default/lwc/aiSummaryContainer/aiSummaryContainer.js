import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Intake__c.AI_Summary__c',
    'Intake__c.Qualification_Score__c'
];

export default class AiSummaryContainer extends LightningElement {

    @api recordId;

    displayedText = '';
    fullText = '';
    isLoading = true;

    confidence = 0;

    typingIndex = 0;
    typingSpeed = 15;

    typingInterval;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: FIELDS
    })
    wiredRecord({ error, data }) {

        if (data) {

            this.fullText =
                data.fields.AI_Summary__c.value ||
                'No AI summary available.';

            this.confidence =
                data.fields.Qualification_Score__c.value || 0;

            this.startTypingAnimation();
        }

        if (error) {
            console.error(
                'AI Summary Error',
                JSON.stringify(error)
            );
        }
    }

    get leadTemperature() {

        if (this.confidence >= 80) {
            return '🔥 Hot Lead';
        }

        if (this.confidence >= 60) {
            return '🟡 Warm Lead';
        }

        return '🔵 Cold Lead';
    }

    startTypingAnimation() {

        if (this.typingInterval) {
            clearInterval(this.typingInterval);
        }

        this.displayedText = '';
        this.typingIndex = 0;
        this.isLoading = true;

        this.typingInterval = setInterval(() => {

            if (this.typingIndex < this.fullText.length) {

                this.displayedText +=
                    this.fullText.charAt(
                        this.typingIndex
                    );

                this.typingIndex++;

            } else {

                clearInterval(
                    this.typingInterval
                );

                this.isLoading = false;
            }

        }, this.typingSpeed);
    }

    disconnectedCallback() {

        if (this.typingInterval) {
            clearInterval(
                this.typingInterval
            );
        }
    }
}