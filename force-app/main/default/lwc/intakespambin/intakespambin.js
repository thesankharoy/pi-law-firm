import { LightningElement, track } from 'lwc';
import getSpamBin    from '@salesforce/apex/IntakeSpamFilterController.getSpamBin';
import recoverIntake from '@salesforce/apex/IntakeSpamFilterController.recoverIntake';
import deleteSpam    from '@salesforce/apex/IntakeSpamFilterController.deleteSpam';
import getSpamCount  from '@salesforce/apex/IntakeSpamFilterController.getSpamCount';

const PAGE_SIZE = 5;

export default class Intakespambin extends LightningElement {

    @track rows      = [];
    @track spamCount = 0;
    @track isLoading = false;
    @track toast     = null;

    currentPage  = 1;
    totalRecords = 0;

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    connectedCallback() {
        this.refresh();
    }

    // ── Data loading ──────────────────────────────────────────────────────────
    async refresh() {
        this.isLoading = true;
        try {
            const [page, count] = await Promise.all([
                getSpamBin({ pageSize: PAGE_SIZE, pageNum: this.currentPage }),
                getSpamCount()
            ]);
            this.totalRecords = page.total;
            this.rows         = this.buildRows(page.records || []);
            this.spamCount    = count;
        } catch (e) {
            this.showToast('Error loading spam bin: ' + this.extractError(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    buildRows(records) {
        return records.map(r => ({
            ...r,
            recordUrl:     '/lightning/r/Intake__c/' + r.id + '/view',
            aiReasonShort: r.aiReason ? r.aiReason.substring(0, 90) + (r.aiReason.length > 90 ? '…' : '') : '—',
            scoreBarStyle: 'width:' + Math.min(r.triageScore || 0, 100) + '%;background:' + this.scoreColor(r.triageScore) + ';height:6px;border-radius:3px;',
        }));
    }

    scoreColor(score) {
        if (!score) return '#d1fae5';
        if (score >= 65) return '#ef4444';
        if (score >= 30) return '#f59e0b';
        return '#10b981';
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    async handleRecover(e) {
        const id = e.currentTarget.dataset.id;
        this.isLoading = true;
        try {
            await recoverIntake({ intakeId: id });
            this.showToast('Lead recovered and moved to New Intake.', 'success');
            this.refresh();
        } catch (err) {
            this.showToast('Could not recover lead: ' + this.extractError(err), 'error');
            this.isLoading = false;
        }
    }

    async handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        const confirmed = window.confirm('Delete this record permanently? This cannot be undone from here.');
        if (!confirmed) {
            return;
        }
        this.isLoading = true;
        try {
            await deleteSpam({ intakeId: id });
            this.showToast('Spam record deleted.', 'success');
            this.refresh();
        } catch (err) {
            this.showToast('Could not delete: ' + this.extractError(err), 'error');
            this.isLoading = false;
        }
    }

    // ── Pagination ────────────────────────────────────────────────────────────
    prevPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.refresh();
        }
    }

    nextPage() {
        if (!this.isLastPage) {
            this.currentPage++;
            this.refresh();
        }
    }

    // ── Computed getters ─────────────────────────────────────────────────────
    get isEmpty()     { return !this.isLoading && this.rows.length === 0; }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage()  { return this.currentPage * PAGE_SIZE >= this.totalRecords; }
    get pageInfo() {
        const start = ((this.currentPage - 1) * PAGE_SIZE) + 1;
        const end   = Math.min(this.currentPage * PAGE_SIZE, this.totalRecords);
        return `Showing ${start}–${end} of ${this.totalRecords}`;
    }

    // ── Toast ─────────────────────────────────────────────────────────────────
    showToast(msg, type) {
        this.toast = { msg, cls: 'toast toast--' + type };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.toast = null; }, 4000);
    }

    extractError(e) {
        return (e.body && e.body.message) ? e.body.message : (e.message || 'Unknown error');
    }
}