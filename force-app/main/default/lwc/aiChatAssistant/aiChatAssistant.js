import { LightningElement, api } from 'lwc';
import askAssistant from '@salesforce/apex/IntakeClaudeChat.askAssistant';

const SUGGESTIONS = [
    { id: 's1', label: 'Summarize this case',     text: 'Summarize this case.' },
    { id: 's2', label: 'Recommended next steps',  text: 'What are the recommended next steps?' },
    { id: 's3', label: 'Case risks',              text: 'What are the main risks for this case?' },
    { id: 's4', label: 'Insurance info needed',   text: 'What insurance information do we still need?' }
];

export default class AiChatAssistant extends LightningElement {

    @api recordId;

    messages = [];
    draft = '';
    isThinking = false;
    suggestions = SUGGESTIONS;
    _id = 0;

    get isEmpty()      { return this.messages.length === 0 && !this.isThinking; }
    get hasMessages()  { return this.messages.length > 0; }
    get sendDisabled() { return this.isThinking || !this.draft.trim(); }

    handleInput(e) {
        this.draft = e.target.value;
        this.autoGrow(e.target);
    }

    handleKeyDown(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSend();
        }
    }

    handleChip(e) {
        this.draft = e.currentTarget.dataset.text;
        this.handleSend();
    }

    handleClear() {
        this.messages = [];
        this.draft = '';
        this.resetInput();
    }

    async handleSend() {
        const text = this.draft.trim();
        if (!text || this.isThinking) return;

        const history = this.buildHistory();   // prior turns only
        this.addMessage('user', text);
        this.draft = '';
        this.resetInput();
        this.isThinking = true;

        try {
            const answer = await askAssistant({
                recordId: this.recordId,
                userQuestion: text,
                conversationHistory: history
            });
            this.addMessage('assistant', answer);
        } catch (err) {
            this.addMessage(
                'assistant',
                'Sorry — something went wrong: ' + (err?.body?.message || err?.message || 'Unknown error'),
                true
            );
        } finally {
            this.isThinking = false;
        }
    }

    addMessage(role, text, isError) {
        const isUser = role === 'user';
        const bubble = isUser
            ? 'bubble bubble-user'
            : (isError ? 'bubble bubble-assistant bubble-error' : 'bubble bubble-assistant');
        this.messages = [...this.messages, {
            id: `m-${this._id++}`,
            isUser,
            text,
            rowClass: isUser ? 'row row-user' : 'row row-assistant',
            bubbleClass: bubble
        }];
        this.scrollToBottom();
    }

    buildHistory() {
        return this.messages
            .map((m) => `${m.isUser ? 'User' : 'Assistant'}: ${m.text}`)
            .join('\n');
    }

    autoGrow(el) {
        el.style.height = 'auto';
        el.style.height = Math.min(el.scrollHeight, 120) + 'px';
    }

    resetInput() {
        const el = this.refs.composerInput;
        if (el) { el.value = ''; el.style.height = 'auto'; }
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            const box = this.refs?.messages;
            if (box) box.scrollTop = box.scrollHeight;
        });
    }
}