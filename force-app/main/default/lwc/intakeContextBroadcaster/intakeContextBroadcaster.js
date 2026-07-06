import { LightningElement, api, wire } from 'lwc';
import { publish, subscribe, MessageContext } from 'lightning/messageService';
import INTAKE_CONTEXT_CHANNEL from '@salesforce/messageChannel/intakeContext__c';

export default class IntakeContextBroadcaster extends LightningElement {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        console.log('[Broadcaster] recordId set:', value);
        this._recordId = value;
    }

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        console.log('[Broadcaster] connectedCallback, recordId =', this._recordId);

        // Subscribe to listen for requests from utility bar
        subscribe(this.messageContext, INTAKE_CONTEXT_CHANNEL, (message) => {
            console.log('[Broadcaster] Received message:', JSON.stringify(message));

            // If utility bar is requesting the current record Id, respond
            if (message.requestId === true && this._recordId) {
                console.log('[Broadcaster] Responding to request with intakeId:', this._recordId);
                publish(this.messageContext, INTAKE_CONTEXT_CHANNEL, {
                    intakeId: this._recordId,
                    requestId: false
                });
            }
        });
    }
}