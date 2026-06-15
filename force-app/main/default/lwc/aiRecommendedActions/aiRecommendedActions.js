import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = [
    'Intake__c.AI_Recommended_Action__c'
];

export default class AiRecommendedActions extends LightningElement {

    @api recordId;

    sections = [];

    currentIndex = 0;

    displayedContent = '';

    isTyping = false;

    typingInterval;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: FIELDS
    })
    wiredRecord({ error, data }) {

        if (data) {

            const rawText =
                data.fields.AI_Recommended_Action__c.value || '';

            this.parseSections(rawText);

            if (this.sections.length) {
                this.showCurrentSection();
            }
        }

        if (error) {
            console.error(
                'AI Recommended Actions Error',
                error
            );
        }
    }

    parseSections(text) {

        const parts = text.split('## ');

        this.sections = parts
            .filter(part => part.trim())
            .map(part => {

                const lines = part.split('\n');

                return {
                    title: lines[0].trim(),
                    content: lines
                        .slice(1)
                        .join('\n')
                        .trim()
                };
            });

        if (!this.sections.length) {

            this.sections = [{
                title: 'No Recommendations',
                content:
                    'No AI recommendations available.'
            }];
        }
    }

    showCurrentSection() {

        clearInterval(this.typingInterval);

        this.displayedContent = '';

        this.isTyping = true;

        const content =
            this.sections[this.currentIndex].content;

        let index = 0;

        this.typingInterval = setInterval(() => {

            if (index < content.length) {

                this.displayedContent +=
                    content.charAt(index);

                index++;

            } else {

                clearInterval(
                    this.typingInterval
                );

                this.isTyping = false;
            }

        }, 10);
    }

    handleNext() {

        if (
            this.currentIndex <
            this.sections.length - 1
        ) {

            this.currentIndex++;

            this.showCurrentSection();
        }
    }

    handlePrevious() {

        if (this.currentIndex > 0) {

            this.currentIndex--;

            this.showCurrentSection();
        }
    }

    get currentSection() {

        return (
            this.sections[this.currentIndex] || {}
        );
    }

    get isFirst() {

        return this.currentIndex === 0;
    }

    get isLast() {

        return (
            this.currentIndex ===
            this.sections.length - 1
        );
    }

    get currentIndexDisplay() {

        return `${this.currentIndex + 1} of ${this.sections.length}`;
    }

    get progressValue() {

        if (!this.sections.length) {
            return 0;
        }

        return (
            ((this.currentIndex + 1)
                / this.sections.length) * 100
        );
    }

    disconnectedCallback() {

        clearInterval(
            this.typingInterval
        );
    }
}