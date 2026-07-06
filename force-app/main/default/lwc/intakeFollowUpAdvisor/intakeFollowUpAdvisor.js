import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRecommendation from "@salesforce/apex/ContactIntelligenceController.getRecommendation";
import refreshRecommendation from "@salesforce/apex/ContactIntelligenceController.refreshRecommendation";
import getIntakeTasks from "@salesforce/apex/ContactIntelligenceController.getIntakeTasks";

const TYPE_ICON = { Call: "📞", SMS: "💬", Email: "✉️" };

export default class IntakeFollowUpAdvisor extends LightningElement {
    @api recordId;

    @track rec = null;
    @track rawTasks = [];
    @track isLoading = true;
    @track isRefreshing = false;
    @track recError = false;

    async connectedCallback() {
        if (!this.recordId) return;
        await Promise.all([this.loadRecommendation(), this.loadTasks()]);
    }

    // ── Load recommendation (may be slow — Claude API) ──────────────
    async loadRecommendation() {
        this.isLoading = true;
        this.recError = false;
        try {
            this.rec = await getRecommendation({ intakeId: this.recordId });
        } catch (e) {
            this.recError = true;
            console.error("Contact Intelligence error:", this.errMsg(e));
        } finally {
            this.isLoading = false;
        }
    }

    // ── Load tasks (fast — SOQL only) ───────────────────────────────
    async loadTasks() {
        try {
            this.rawTasks = await getIntakeTasks({ intakeId: this.recordId });
        } catch (e) {
            console.error("Task load error:", this.errMsg(e));
        }
    }

    // ── Force refresh ───────────────────────────────────────────────
    async handleRefresh() {
        this.isRefreshing = true;
        this.recError = false;
        try {
            this.rec = await refreshRecommendation({ intakeId: this.recordId });
        } catch (e) {
            this.recError = true;
            this.toast("Could not refresh", this.errMsg(e), "error");
        } finally {
            this.isRefreshing = false;
        }
    }

    // ── Getters ──────────────────────────────────────────────────────
    get hasTasks() {
        return this.rawTasks.length > 0;
    }

    get refreshIconClass() {
        return this.isRefreshing ? "spin-icon" : "";
    }

    get confidencePillClass() {
        const c = this.rec?.confidence || "low";
        return `conf-pill conf-${c}`;
    }

    // Group tasks by Day label and attach AI hints
    get groupedDays() {
        const groups = {};
        (this.rawTasks || []).forEach((t) => {
            // Extract "Day 1" / "Day 2" from subject
            const match = t.subject.match(/Day (\d)/);
            const dayKey = match ? `Day ${match[1]}` : "Upcoming";
            if (!groups[dayKey]) groups[dayKey] = [];
            groups[dayKey].push(this.enrichTask(t));
        });

        return Object.keys(groups)
            .sort()
            .map((label) => ({
                label,
                tasks: groups[label]
            }));
    }

    enrichTask(t) {
        const type = t.type || "";
        const isPrimary = this.rec && type === this.rec.primaryChannel;
        const hint = this.hintFor(type);

        // Strip emoji prefix from subject for cleaner display
        const displaySubject = t.subject.replace(/^Day \d+ /, "").trim();

        return {
            ...t,
            typeIcon: TYPE_ICON[type] || "📋",
            displaySubject,
            hint,
            hintClass: isPrimary
                ? "task-hint hint-primary"
                : hint
                  ? "task-hint hint-secondary"
                  : "task-hint hint-neutral"
        };
    }

    hintFor(type) {
        if (!this.rec) return "";
        if (type === "Call") return this.rec.callHint || "";
        if (type === "SMS") return this.rec.smsHint || "";
        if (type === "Email") return this.rec.emailHint || "";
        return "";
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}