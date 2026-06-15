import { LightningElement } from 'lwc';

export default class IntakeSoftphone extends LightningElement {

    connectedCallback() {
        window.addEventListener('message', this.handleMessage.bind(this));
    }

    disconnectedCallback() {
        window.removeEventListener('message', this.handleMessage.bind(this));
    }

    handleMessage(event) {
        if (!event.data || event.data.source !== 'twilio-softphone') return;

        const { type, payload } = event.data;
        console.log('Softphone event:', type, payload);

        // Fire LWC events or update state here as needed
        // e.g. this.dispatchEvent(new CustomEvent(type, { detail: payload }));
    }

    // Call this from anywhere in your LWC to dial a number programmatically
    dialNumber(number) {
        const iframe = this.template.querySelector('iframe');
        if (iframe) {
            iframe.contentWindow.postMessage(
                { target: 'twilio-softphone', command: 'call', number },
                '*'
            );
        }
    }
}