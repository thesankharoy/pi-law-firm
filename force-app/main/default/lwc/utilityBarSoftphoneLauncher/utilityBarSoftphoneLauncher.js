import { LightningElement, wire } from 'lwc';
import { subscribe, MessageContext } from 'lightning/messageService';
import INTAKE_CONTEXT_CHANNEL from '@salesforce/messageChannel/intakeContext__c';

export default class UtilityBarSoftphoneLauncher extends LightningElement {
    currentIntakeId = null;
    softphoneWin = null;
    buttonLabel = '📞 Open Softphone';

    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        console.log('[UtilityBar] connectedCallback - subscribing');
        subscribe(this.messageContext, INTAKE_CONTEXT_CHANNEL, (message) => {
            console.log('[UtilityBar] Received message:', JSON.stringify(message));
            this.currentIntakeId = message.intakeId;
        });
    }

    openSoftphone() {
        console.log('[UtilityBar] Button clicked, currentIntakeId =', this.currentIntakeId);

        if (this.softphoneWin && !this.softphoneWin.closed) {
            this.softphoneWin.focus();
            return;
        }

        var url = '/apex/TwilioSoftphone';
        if (this.currentIntakeId) {
            url += '?intakeId=' + this.currentIntakeId;
        }

        console.log('[UtilityBar] Opening softphone:', url);

        this.softphoneWin = window.open(
            url,
            'twilioSoftphone',
            'width=380,height=680,resizable=yes,alwaysRaised=yes'
        );

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