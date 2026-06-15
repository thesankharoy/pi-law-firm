import { LightningElement, api, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import INTAKE_CONTEXT_CHANNEL from '@salesforce/messageChannel/intakeContext__c';

export default class IntakeContextBroadcaster extends LightningElement {
    @api recordId;

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        console.log('[Broadcaster] connectedCallback, recordId =', this.recordId);
        this.tryPublish();
    }

    renderedCallback() {
        console.log('[Broadcaster] renderedCallback, recordId =', this.recordId);
        this.tryPublish();
    }

    tryPublish() {
        if (this.recordId && !this._published) {
            this._published = true;
            console.log('[Broadcaster] Publishing intakeId:', this.recordId);
            publish(this.messageContext, INTAKE_CONTEXT_CHANNEL, {
                intakeId: this.recordId
            });
        }
    }
}