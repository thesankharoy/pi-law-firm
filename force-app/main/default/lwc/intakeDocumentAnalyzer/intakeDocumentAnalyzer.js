import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import listDocuments from "@salesforce/apex/DocumentAnalysisController.listDocuments";
import getAnalysis from "@salesforce/apex/DocumentAnalysisController.getAnalysis";
import analyzeDocument from "@salesforce/apex/DocumentAnalysisController.analyzeDocument";

// Order + labels for rendering the extracted fact sections.
const SECTION_DEFS = [
    { key: "keyDates", title: "Key Dates", kind: "pairs", primary: "label", secondary: "date" },
    { key: "parties", title: "Parties", kind: "pairs", primary: "name", secondary: "role" },
    { key: "providers", title: "Providers", kind: "pairs", primary: "name", secondary: "type" },
    { key: "injuries", title: "Injuries / Diagnoses", kind: "list" },
    { key: "amounts", title: "Amounts", kind: "pairs", primary: "label", secondary: "value" },
    { key: "identifiers", title: "Identifiers", kind: "pairs", primary: "label", secondary: "value" },
    { key: "actionItems", title: "Action Items", kind: "list" }
];

export default class IntakeDocumentAnalyzer extends LightningElement {
    @api recordId; // Intake Id from the record page

    @track files = [];
    @track sections = [];
    @track isLoading = true;
    @track isAnalyzing = false;

    selectedDocId = null;
    analysis = null; // current AnalysisDTO or null

    connectedCallback() {
        if (this.recordId) this.loadFiles();
    }

    async loadFiles() {
        this.isLoading = true;
        try {
            const rows = await listDocuments({ intakeId: this.recordId });
            this.files = rows.map((r) => this.decorateRow(r));
        } catch (e) {
            this.toast("Couldn't load files", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    decorateRow(r) {
        const selected = r.documentId === this.selectedDocId;
        let statusLabel = "Not analyzed";
        let statusClass = "badge badge-neutral";
        if (!r.analyzable) {
            statusLabel = "Unsupported";
            statusClass = "badge badge-muted";
        } else if (r.analyzed) {
            statusLabel = r.documentType || "Analyzed";
            statusClass = "badge badge-done";
        }
        return {
            ...r,
            statusLabel,
            statusClass,
            notAnalyzable: !r.analyzable,
            rowClass: selected ? "file-row file-row-selected" : "file-row"
        };
    }

    // ── Selection ────────────────────────────────────────────────────
    async handleSelect(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.files.find((f) => f.documentId === id);
        if (!row || !row.analyzable) return;

        this.selectedDocId = id;
        this.files = this.files.map((f) => this.decorateRow(f));
        this.analysis = null;
        this.sections = [];

        // Pull the cached analysis (if any) for this file.
        this.isAnalyzing = true;
        try {
            const dto = await getAnalysis({ documentId: id });
            if (dto) this.renderAnalysis(dto);
        } catch (err) {
            this.toast("Couldn't load analysis", this.errMsg(err), "error");
        } finally {
            this.isAnalyzing = false;
        }
    }

    // ── Analyze / Re-analyze ─────────────────────────────────────────
    handleAnalyze() {
        this.runAnalysis(false);
    }
    handleReanalyze() {
        this.runAnalysis(true);
    }

    async runAnalysis(force) {
        if (!this.selectedDocId) return;
        this.isAnalyzing = true;
        try {
            const dto = await analyzeDocument({ documentId: this.selectedDocId, force });
            this.renderAnalysis(dto);
            await this.loadFiles(); // refresh status badges
            this.toast("Analysis complete", this.selectedFileName, "success");
        } catch (e) {
            this.toast("Analysis failed", this.errMsg(e), "error");
        } finally {
            this.isAnalyzing = false;
        }
    }

    renderAnalysis(dto) {
        this.analysis = dto;
        let facts = {};
        try {
            facts = JSON.parse(dto.extractedJson || "{}");
        } catch (e) {
            facts = {};
        }
        this.sections = this.buildSections(facts);
    }

    buildSections(facts) {
        const out = [];
        for (const def of SECTION_DEFS) {
            const arr = Array.isArray(facts[def.key]) ? facts[def.key] : [];
            if (!arr.length) continue;
            if (def.kind === "pairs") {
                out.push({
                    key: def.key,
                    title: def.title,
                    isPairs: true,
                    isList: false,
                    items: arr.map((o, i) => ({
                        key: `${def.key}-${i}`,
                        primary: this.val(o, def.primary),
                        secondary: this.val(o, def.secondary)
                    }))
                });
            } else {
                out.push({
                    key: def.key,
                    title: def.title,
                    isPairs: false,
                    isList: true,
                    items: arr.map((v, i) => ({
                        key: `${def.key}-${i}`,
                        text: typeof v === "string" ? v : JSON.stringify(v)
                    }))
                });
            }
        }
        return out;
    }

    val(obj, field) {
        if (obj == null) return "";
        if (typeof obj === "string") return obj;
        const v = obj[field];
        return v == null ? "" : String(v);
    }

    // ── Derived state ────────────────────────────────────────────────
    get hasFiles() {
        return this.files.length > 0;
    }
    get hasSelection() {
        return !!this.selectedDocId;
    }
    get hasAnalysis() {
        return !!this.analysis;
    }
    get showAnalyzePrompt() {
        return this.hasSelection && !this.analysis && !this.isAnalyzing;
    }
    get selectedFileName() {
        const row = this.files.find((f) => f.documentId === this.selectedDocId);
        return row ? row.name : "";
    }
    get usageLabel() {
        if (!this.analysis || this.analysis.inputTokens == null) return "";
        return `${this.analysis.inputTokens} in / ${this.analysis.outputTokens} out tokens`;
    }

    // ── Utils ────────────────────────────────────────────────────────
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}