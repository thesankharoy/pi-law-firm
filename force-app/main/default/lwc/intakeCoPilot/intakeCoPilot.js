import { LightningElement, api, track } from 'lwc';
import getContext from '@salesforce/apex/IntakeCoPilotController.getContext';
import analyzeTurn from '@salesforce/apex/IntakeCoPilotController.analyzeTurn';

/**
 * Live in-call co-pilot panel — REAL AUDIO ONLY (no demo/simulation).
 *
 * Turns arrive solely from the Twilio softphone, which posts
 * {source:'twilio-softphone', type:'copilot-transcript', payload:{transcript,language,turnType}}
 * via window.postMessage. The panel auto-arms when a call connects and clears
 * when it disconnects. For each turn we render the transcript, call Claude, then
 * fill in the translation + suggestion.
 */
export default class IntakeCoPilot extends LightningElement {
    @api recordId;

    @track turns = [];
    @track sentiment = '';
    @track leadFit = '';
    @track clientName = '';
    @track incidentType = '';
    @track listening = false;
    @track phoneReady = false;
    @track heardCount = 0;

    _seq = 0;
    _onMessage;

    connectedCallback() {
        this.loadContext();
        this._onMessage = (event) => this.handleWindowMessage(event);
        window.addEventListener('message', this._onMessage);
        // eslint-disable-next-line no-console
        console.log('[CoPilot] panel mounted, listening for softphone messages');
    }

    disconnectedCallback() {
        if (this._onMessage) {
            window.removeEventListener('message', this._onMessage);
        }
    }

    loadContext() {
        getContext({ intakeId: this.recordId })
            .then((ctx) => {
                this.clientName = ctx.clientName;
                this.incidentType = ctx.incidentType;
            })
            .catch(() => {
                /* header is best-effort */
            });
    }

    // ----- manual start / stop (arms the listener; does NOT fabricate data) -----
    toggleListening() {
        if (this.listening) {
            this.listening = false;
        } else {
            this.listening = true;
            this.turns = [];
            this.heardCount = 0;
            this.sentiment = '';
            this.leadFit = '';
        }
    }

    // ----- real softphone feed -----
    handleWindowMessage(event) {
        const d = event && event.data;
        if (!d || d.source !== 'twilio-softphone') {
            return;
        }
        // eslint-disable-next-line no-console
        console.log('[CoPilot] softphone message:', d.type, d.payload || '');

        if (d.type === 'registered') {
            this.phoneReady = true;
            return;
        }
        if (d.type === 'connected') {
            // Call answered — auto-arm and start a fresh session.
            this.phoneReady = true;
            this.listening = true;
            this.turns = [];
            this.heardCount = 0;
            this.sentiment = '';
            this.leadFit = '';
            return;
        }
        if (d.type === 'disconnected' || d.type === 'cancelled' || d.type === 'rejected') {
            this.listening = false;
            return;
        }
        if (d.type === 'copilot-transcript' && d.payload && d.payload.transcript) {
            this.heardCount += 1;
            this.listening = true;
            this.processTurn(d.payload.transcript, d.payload.language, d.payload.turnType || 'client');
        }
    }

    processTurn(transcript, language, turnType) {
        this._seq += 1;
        const turnKey = `t${this._seq}`;
        const newTurn = {
            key: turnKey,
            rowClass: turnType === 'client' ? 'turn turn_client' : 'turn turn_specialist',
            speaker: turnType === 'client' ? this.clientName || 'Client' : 'Specialist',
            transcript,
            translation: '',
            language,
            showTranslation: false,
            analyzing: true,
            suggestion: '',
            errorMsg: ''
        };
        this.turns = [...this.turns, newTurn].slice(-50);
        this.scrollFeed();

        analyzeTurn({ transcript, language, intakeId: this.recordId })
            .then((r) => {
                this.patchTurn(turnKey, {
                    translation: r.translation || '',
                    showTranslation: !!r.translation,
                    language: r.language || language,
                    suggestion: r.suggestion || '',
                    analyzing: false
                });
                if (r.sentiment) {
                    this.sentiment = r.sentiment;
                }
                if (r.leadFit) {
                    this.leadFit = r.leadFit;
                }
                this.scrollFeed();
            })
            .catch((error) => {
                const msg =
                    (error && error.body && error.body.message) ||
                    (error && error.message) ||
                    'Analysis failed';
                this.patchTurn(turnKey, { analyzing: false, errorMsg: msg });
                // eslint-disable-next-line no-console
                console.error('[CoPilot] analyzeTurn failed', msg);
            });
    }

    patchTurn(key, patch) {
        this.turns = this.turns.map((t) => (t.key === key ? { ...t, ...patch } : t));
    }

    scrollFeed() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => {
            const feed = this.template.querySelector('.feed');
            if (feed) {
                feed.scrollTop = feed.scrollHeight;
            }
        });
    }

    // ----- view helpers -----
    get statusPillClass() {
        return this.listening ? 'pill pill_live' : 'pill pill_idle';
    }
    get statusLabel() {
        return this.listening ? 'Listening' : 'Idle';
    }
    get toggleLabel() {
        return this.listening ? 'Stop' : 'Start';
    }
    get toggleVariant() {
        return this.listening ? 'destructive' : 'brand';
    }
    get toggleIcon() {
        return this.listening ? 'utility:stop' : 'utility:play';
    }
    get sentimentClass() {
        const s = (this.sentiment || '').toLowerCase();
        return `badge badge_${s || 'neutral'}`;
    }
    get leadFitClass() {
        const f = (this.leadFit || '').toLowerCase().replace(/\s+/g, '');
        return `badge badge_fit_${f || 'moderate'}`;
    }
    get hasTurns() {
        return this.turns.length > 0;
    }
    get emptyTitle() {
        if (this.listening) {
            return 'Listening to the call…';
        }
        return this.phoneReady ? 'Ready — answer a call' : 'Waiting for the softphone';
    }
    get emptySub() {
        if (this.listening) {
            return 'Transcription appears here as the caller speaks. Nothing yet — speak on the line.';
        }
        return 'When a call connects, this panel arms automatically and shows live transcription, translation and coaching.';
    }
    get debugLine() {
        return `phone: ${this.phoneReady ? 'ready' : 'not ready'} · segments heard: ${this.heardCount}`;
    }
}