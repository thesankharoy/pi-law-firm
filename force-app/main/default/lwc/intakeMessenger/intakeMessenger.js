import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConversation from '@salesforce/apex/IntakeMessagingController.getConversation';
import sendReply from '@salesforce/apex/IntakeMessagingController.sendReply';

const POLL_MS = 5000;

export default class IntakeMessenger extends LightningElement {
    @api recordId;

    @track messages = [];
    clientName = 'Client';
    leadPhone;
    canReply = false;
    botActive = false;

    draft = '';
    loading = true;
    sending = false;
    error;

    _pollId;
    _lastCount = -1;

    connectedCallback() {
        this.load(true);
        this._pollId = setInterval(() => this.load(false), POLL_MS);
    }

    disconnectedCallback() {
        if (this._pollId) clearInterval(this._pollId);
    }

    async load(showSpinner) {
        if (showSpinner) this.loading = true;
        try {
            const c = await getConversation({ intakeId: this.recordId });
            this.applyConversation(c);
            this.error = undefined;
        } catch (e) {
            this.error = this.reason(e);
        } finally {
            this.loading = false;
        }
    }

    applyConversation(c) {
        this.clientName = c.clientName || 'Client';
        this.leadPhone = c.leadPhone;
        this.canReply = c.canReply;
        this.botActive = c.botActive;
        this.messages = (c.messages || []).map((m) => this.decorate(m));
        // Auto-scroll only when the thread actually grew.
        if (this.messages.length !== this._lastCount) {
            this._lastCount = this.messages.length;
            this.scrollToBottom();
        }
    }

    decorate(m) {
        const cls = ['bubble-row', m.outbound ? 'out' : 'in'].join(' ');
        let author;
        if (!m.outbound) author = this.clientName;
        else if (m.fromBot) author = 'AI Assistant';
        else author = 'You';
        return {
            id: m.id,
            body: m.body,
            author,
            fromBot: m.fromBot,
            time: this.formatTime(m.sentAt),
            rowClass: cls,
            bubbleClass: ['bubble', m.outbound ? 'bubble-out' : 'bubble-in', m.fromBot ? 'bubble-bot' : ''].join(' ')
        };
    }

    handleInput(e) {
        this.draft = e.target.value;
    }

    handleKeyDown(e) {
        // Enter sends, Shift+Enter = newline.
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSend();
        }
    }

    async handleSend() {
        const body = (this.draft || '').trim();
        if (!body || this.sending) return;
        if (!this.canReply) {
            this.toast('Can’t send', 'No phone number on file for this lead.', 'error');
            return;
        }
        this.sending = true;
        try {
            const c = await sendReply({ intakeId: this.recordId, body });
            this.draft = '';
            this.applyConversation(c);
        } catch (e) {
            this.toast('Message not sent', this.reason(e), 'error');
        } finally {
            this.sending = false;
        }
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector('.thread');
            if (el) el.scrollTop = el.scrollHeight;
        }, 0);
    }

    formatTime(dt) {
        if (!dt) return '';
        const d = new Date(dt);
        return d.toLocaleString(undefined, {
            month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit'
        });
    }

    reason(e) {
        return e?.body?.message || e?.message || 'Something went wrong.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    get showEmpty() {
        return !this.loading && !this.hasMessages;
    }

    get sendDisabled() {
        return this.sending || !this.draft || !this.draft.trim();
    }

    get statusLabel() {
        return this.botActive ? 'AI assistant active' : 'You’re handling this';
    }

    get statusClass() {
        return this.botActive ? 'status status-bot' : 'status status-human';
    }
}