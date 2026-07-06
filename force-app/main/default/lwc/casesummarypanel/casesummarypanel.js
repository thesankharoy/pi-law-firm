import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';

import getSummary        from '@salesforce/apex/CaseSummaryController.getSummary';
import setReviewed       from '@salesforce/apex/CaseSummaryController.setReviewed';
import saveSummary       from '@salesforce/apex/CaseSummaryController.saveSummary';
import regenerateSummary from '@salesforce/apex/CaseSummaryController.regenerateSummary';

// How long to wait between polls when regenerating (ms)
const POLL_INTERVAL_MS = 5000;
// How many polls before we give up
const POLL_MAX_ATTEMPTS = 24; // 2 minutes max

// Matches a section header line like "CLIENT:" or "INJURIES AND TREATMENT:"
// at the start of a line — short, all-caps (with spaces/&), ending in a colon.
const SECTION_HEADER_REGEX = /^([A-Z][A-Z &/]{1,40}):\s*$/;

export default class CaseSummaryPanel extends LightningElement {

    @api recordId;

    // Wired result ref — kept for refreshApex
    _wiredSummaryResult;

    @track summaryData    = null;
    @track isLoading      = true;
    @track isRegenerating = false;
    @track isSaving       = false;
    @track isEditing      = false;
    @track editBuffer     = '';
    @track hasError       = false;
    @track errorMessage   = '';

    _pollTimer    = null;
    _pollAttempts = 0;

    // ── Wire ────────────────────────────────────────────────────────────────

    @wire(getSummary, { intakeId: '$recordId' })
    wiredSummary(result) {
        this._wiredSummaryResult = result;
        this.isLoading = false;

        if (result.data) {
            this.summaryData = result.data;
            this.hasError    = false;

            // If we were polling for a newly-generated summary, stop when it arrives
            if (this.isRegenerating && result.data.summary) {
                this.isRegenerating = false;
                this._stopPolling();
                this._toast('Summary ready', 'Case summary generated successfully.', 'success');
            }
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error.body?.message || 'Error loading summary.';
        }
    }

    // ── Derived getters ──────────────────────────────────────────────────────

    get hasSummary() {
        return !!(this.summaryData?.summary);
    }

    get summaryText() {
        return this.summaryData?.summary || '';
    }

    /**
     * Parses the raw summary text into an array of { key, label, body }
     * sections so the template can render styled headings instead of one
     * flat text block. Falls back to a single unlabeled section if no
     * "LABEL:" headers are found (so unexpected formats still display).
     */
    get summarySections() {
        const text = this.summaryText;
        if (!text) return [];

        const lines = text.split('\n');
        const sections = [];
        let current = null;

        lines.forEach((line) => {
            const match = line.match(SECTION_HEADER_REGEX);
            if (match) {
                current = { key: match[1], label: match[1], lines: [] };
                sections.push(current);
            } else if (current) {
                current.lines.push(line);
            } else {
                // Content before any recognized header — keep it visible.
                if (!sections.length || sections[0].key !== '__preamble__') {
                    current = { key: '__preamble__', label: '', lines: [] };
                    sections.unshift(current);
                }
                current.lines.push(line);
            }
        });

        return sections
            .map((s) => ({
                key: s.key,
                label: s.label,
                body: s.lines.join('\n').trim()
            }))
            .filter((s) => s.body.length > 0 || s.label.length > 0);
    }

    get isReviewed() {
        return !!(this.summaryData?.reviewed);
    }

    get intakeName() {
        return this.summaryData?.intakeName || '';
    }

    get formattedGeneratedAt() {
        const raw = this.summaryData?.generatedAt;
        if (!raw) return '—';
        return new Date(raw).toLocaleString('en-US', {
            month: 'short', day: 'numeric', year: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });
    }

    get reviewedLabel() {
        return this.isReviewed ? '✓ Mark Unreviewed' : '✓ Mark Reviewed';
    }

    get regenerateLabel() {
        return this.isRegenerating ? 'Generating…' : '↻ Regenerate';
    }

    get saveLabel() {
        return this.isSaving ? 'Saving…' : 'Save';
    }

    // ── Reviewed toggle ──────────────────────────────────────────────────────

    async handleToggleReviewed() {
        const next = !this.isReviewed;
        this.isSaving = true;
        try {
            await setReviewed({ intakeId: this.recordId, reviewed: next });
            await refreshApex(this._wiredSummaryResult);
            getRecordNotifyChange([{ recordId: this.recordId }]);
            this._toast(
                next ? 'Marked as reviewed' : 'Marked as unreviewed',
                '',
                'success'
            );
        } catch (e) {
            this._toast('Error', e.body?.message || 'Could not update review status.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ── Regenerate ───────────────────────────────────────────────────────────

    async handleRegenerate() {
        this.isRegenerating = true;
        this._pollAttempts  = 0;

        try {
            await regenerateSummary({ intakeId: this.recordId });
            this._startPolling();
        } catch (e) {
            this.isRegenerating = false;
            this._toast('Error', e.body?.message || 'Could not start summary generation.', 'error');
        }
    }

    _startPolling() {
        this._pollTimer = setInterval(async () => {
            this._pollAttempts++;
            await refreshApex(this._wiredSummaryResult);

            if (!this.isRegenerating || this._pollAttempts >= POLL_MAX_ATTEMPTS) {
                this._stopPolling();
                if (this._pollAttempts >= POLL_MAX_ATTEMPTS && this.isRegenerating) {
                    this.isRegenerating = false;
                    this._toast(
                        'Taking longer than expected',
                        'Summary generation is still in progress. Refresh the page in a minute.',
                        'warning'
                    );
                }
            }
        }, POLL_INTERVAL_MS);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    disconnectedCallback() {
        this._stopPolling();
    }

    // ── Edit / save ──────────────────────────────────────────────────────────

    handleStartEdit() {
        this.editBuffer = this.summaryText;
        this.isEditing  = true;
    }

    handleEditChange(e) {
        this.editBuffer = e.target.value;
    }

    handleCancelEdit() {
        this.isEditing  = false;
        this.editBuffer = '';
    }

    async handleSaveEdit() {
        this.isSaving = true;
        try {
            await saveSummary({ intakeId: this.recordId, summaryText: this.editBuffer });
            await refreshApex(this._wiredSummaryResult);
            this.isEditing = false;
            this._toast('Saved', 'Summary updated.', 'success');
        } catch (e) {
            this._toast('Error', e.body?.message || 'Could not save edits.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ── Helper ───────────────────────────────────────────────────────────────

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}