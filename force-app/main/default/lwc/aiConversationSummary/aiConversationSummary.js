import { LightningElement, api } from 'lwc';

import getSummary
    from '@salesforce/apex/IntakeAISummaryService.getSummary';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';

export default class AiConversationSummary extends LightningElement {

    @api recordId;

    loading = false;

    summary;
    sentiment;
    recommendedAction;
    nextMessage;

    connectedCallback() {
        this.loadSummary();
    }

    loadSummary() {

        this.loading = true;

        getSummary({
            intakeId: this.recordId
        })
        .then(result => {

            if (result) {

                this.summary =
                    result.AI_Conversation_Summary__c;

                this.sentiment =
                    result.AI_Sentiment__c;

                this.recommendedAction =
                    result.AI_Next_Recommended_Action__c;

                this.nextMessage =
                    result.AI_Next_Message__c;
            }
        })
        .catch(error => {

            this.showToast(
                'Error',
                error?.body?.message ||
                'Failed to load AI Summary.',
                'error'
            );
        })
        .finally(() => {

            this.loading = false;
        });
    }

    generateSummary() {

        this.showToast(
            'Info',
            'AI Summary generation is now handled by Flow.',
            'info'
        );
    }

    @api
    refreshComponent() {

        this.loadSummary();
    }

    get hasSummary() {

        return !!this.summary;
    }

    get sentimentBannerClass() {

    if (!this.sentiment) {
        return 'sentiment-banner neutral';
    }

    const value =
        this.sentiment.toLowerCase();

    if (value.includes('positive')) {
        return 'sentiment-banner positive';
    }

    if (value.includes('negative')) {
        return 'sentiment-banner negative';
    }

    if (
        value.includes('urgent') ||
        value.includes('critical') ||
        value.includes('concerned')
    ) {
        return 'sentiment-banner warning';
    }

    return 'sentiment-banner neutral';
}

copyMessage() {

    navigator.clipboard.writeText(
        this.nextMessage || ''
    );

    this.showToast(
        'Success',
        'Message copied to clipboard.',
        'success'
    );
}

    get sentimentClass() {

        if (!this.sentiment) {
            return 'sentiment-pill neutral';
        }

        const value =
            this.sentiment.toLowerCase();

        if (
            value.includes('positive')
        ) {
            return 'sentiment-pill positive';
        }

        if (
            value.includes('negative')
        ) {
            return 'sentiment-pill negative';
        }

        if (
            value.includes('concerned') ||
            value.includes('urgent') ||
            value.includes('critical')
        ) {
            return 'sentiment-pill warning';
        }

        return 'sentiment-pill neutral';
    }

    showToast(title, message, variant) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}