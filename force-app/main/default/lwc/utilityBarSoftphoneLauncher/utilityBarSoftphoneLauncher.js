import { LightningElement, wire } from 'lwc';
import { publish, subscribe, MessageContext } from 'lightning/messageService';
import INTAKE_CONTEXT_CHANNEL from '@salesforce/messageChannel/intakeContext__c';

export default class UtilityBarSoftphoneLauncher extends LightningElement {
    currentIntakeId = null;
    softphoneWin = null;
    buttonLabel = '📞 Open Softphone';

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        subscribe(this.messageContext, INTAKE_CONTEXT_CHANNEL, (message) => {
            console.log('[UtilityBar] Received message:', JSON.stringify(message));

            if (message.intakeId && message.requestId === false) {
                this.currentIntakeId = message.intakeId;
                console.log('[UtilityBar] Stored intakeId:', this.currentIntakeId);

                // Handle: window already open and waiting for intakeId
                if (this._waitingToOpen) {
                    this._waitingToOpen = false;
                    clearTimeout(this._openTimer);
                    this._openWindow();
                }
                // Handle: window already open, push intakeId via postMessage
                else if (this.softphoneWin && !this.softphoneWin.closed) {
                    this.softphoneWin.postMessage(
                        { target: 'twilio-softphone', command: 'setIntakeId', intakeId: this.currentIntakeId },
                        '*'
                    );
                }
            }
        });

        // Listen for requests from the VF page popup
        window.addEventListener('message', (event) => {
            if (!event.data || event.data.source !== 'twilio-softphone') return;
            if (event.data.type === 'requestIntakeId') {
                console.log('[UtilityBar] Softphone requested intakeId');
                // Publish LMS request to broadcaster
                publish(this.messageContext, INTAKE_CONTEXT_CHANNEL, { intakeId: null, requestId: true });
                // If we already have it, send immediately too
                if (this.currentIntakeId && this.softphoneWin && !this.softphoneWin.closed) {
                    this.softphoneWin.postMessage(
                        { target: 'twilio-softphone', command: 'setIntakeId', intakeId: this.currentIntakeId },
                        '*'
                    );
                }
            }
        });
    }

    openSoftphone() {
        if (this.softphoneWin && !this.softphoneWin.closed) {
            this.softphoneWin.focus();
            return;
        }

        // Request intakeId first, open window after response
        this._waitingToOpen = true;
        publish(this.messageContext, INTAKE_CONTEXT_CHANNEL, { intakeId: null, requestId: true });

        // Fallback: open without intakeId after 1.5s if no broadcaster response
        this._openTimer = setTimeout(() => {
            if (this._waitingToOpen) {
                console.log('[UtilityBar] No intakeId response, opening without it');
                this._waitingToOpen = false;
                this._openWindow();
            }
        }, 1500);
    }

    _openWindow() {
        var url = '/apex/TwilioSoftphone';
        if (this.currentIntakeId) {
            url += '?intakeId=' + this.currentIntakeId;
        }
        console.log('[UtilityBar] Opening softphone URL:', url);
        this.softphoneWin = window.open(url, 'twilioSoftphone', 'width=380,height=680,resizable=yes,alwaysRaised=yes');
        this.buttonLabel = '📞 Softphone Open';

        var self = this;
        var checkClosed = setInterval(function() {
            if (self.softphoneWin && self.softphoneWin.closed) {
                self.buttonLabel = '📞 Open Softphone';
                self.softphoneWin = null;
                clearInterval(checkClosed);
            }
        }, 1000);
    }
}