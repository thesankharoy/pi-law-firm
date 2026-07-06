import { LightningElement, api } from 'lwc';
import getRecordingUrl from '@salesforce/apex/CallRecordingController.getRecordingUrl';

export default class CallRecordingPlayer extends LightningElement {
    @api recordId;

    recordingUrl;
    loading = true;
    error;

    connectedCallback() {
        this.load();
    }

    // Imperative (not @wire): the controller does a callout and returns a
    // short-lived presigned URL, so it must be cacheable=false — which @wire
    // cannot use. Imperative also fetches a fresh URL on each page load.
    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.recordingUrl = await getRecordingUrl({ recordId: this.recordId });
        } catch (e) {
            this.recordingUrl = undefined;
            this.error = 'Could not load the recording. ' +
                (e && e.body && e.body.message ? e.body.message : '');
        } finally {
            this.loading = false;
        }
    }

    get hasRecording() {
        return !this.loading && !!this.recordingUrl;
    }

    get noRecording() {
        return !this.loading && !this.recordingUrl && !this.error;
    }
}