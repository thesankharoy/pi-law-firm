import { LightningElement, api, wire } from 'lwc';
import getDialInfo from '@salesforce/apex/TwilioTokenServiceVF.getDialInfo';

/**
 * "Call" button for Contact / Intake record pages.
 * Opens the Twilio softphone (VF page) with the intake id + number and auto-dials.
 * No Open CTI / Call Center required.
 */
export default class SoftphoneCallButton extends LightningElement {
    @api recordId;

    phones = [];
    intakeId = '';
    loaded = false;

    @wire(getDialInfo, { recordId: '$recordId' })
    wiredInfo({ data, error }) {
        if (data) {
            this.intakeId = data.intakeId || '';
            this.phones = (data.phones || []).map((p, idx) => ({
                key: idx,
                label: p.label,
                phone: p.phone,
                btnLabel: `Call ${p.label} · ${p.phone}`
            }));
            this.loaded = true;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('getDialInfo failed', JSON.stringify(error));
            this.loaded = true;
        }
    }

    get hasPhones() {
        return this.phones.length > 0;
    }

    get showEmpty() {
        return this.loaded && this.phones.length === 0;
    }

    handleCall(event) {
        const number = event.currentTarget.dataset.number;
        if (!number) {
            return;
        }
        const params = [];
        if (this.intakeId) {
            params.push('intakeId=' + this.intakeId);
        }
        params.push('number=' + encodeURIComponent(number));
        params.push('autodial=1');

        const url = '/apex/TwilioSoftphone?' + params.join('&');
        window.open(url, 'twilioSoftphone', 'width=380,height=680,resizable=yes,alwaysRaised=yes');
    }
}