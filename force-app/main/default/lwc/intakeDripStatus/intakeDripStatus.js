import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getEnrollmentStatus from "@salesforce/apex/DripCampaignController.getEnrollmentStatus";
import deferIntake from "@salesforce/apex/DripCampaignController.deferIntake";
import cancelEnrollment from "@salesforce/apex/DripCampaignController.cancelEnrollment";

export default class IntakeDripStatus extends LightningElement {
    @api recordId;

    @track isLoading = true;
    @track enrollment = { isEnrolled: false };

    // Defer modal
    @track showDeferModal = false;
    @track deferDate = "";
    @track deferError = null;
    @track isDeferring = false;

    async connectedCallback() {
        if (!this.recordId) return;
        await this.loadStatus();
    }

    async loadStatus() {
        this.isLoading = true;
        try {
            this.enrollment = (await getEnrollmentStatus({ intakeId: this.recordId })) || { isEnrolled: false };
        } catch (e) {
            console.error("getEnrollmentStatus:", this.errMsg(e));
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed getters ──────────────────────────────────────────
    get isDeferredEnrollment() {
        return this.enrollment?.isEnrolled && this.enrollment?.type === "Deferred";
    }
    get isReactivationEnrollment() {
        return this.enrollment?.isEnrolled && this.enrollment?.type === "Re-activation";
    }

    get deferredCountdownLabel() {
        const days = this.enrollment?.daysLeft;
        if (days == null) return "";
        if (days < 0) return "Overdue — re-activation pending";
        if (days === 0) return "Re-activates today";
        if (days === 1) return "1 day away";
        return `${days} days away`;
    }

    get progressBarStyle() {
        const pct = this.enrollment?.progressPct || 0;
        return `width:${pct}%;`;
    }

    get todayIso() {
        return new Date().toISOString().substring(0, 10);
    }

    get deferDateLabel() {
        if (!this.deferDate) return "";
        try {
            return new Date(this.deferDate + "T12:00:00").toLocaleDateString("en-US", {
                weekday: "long",
                month: "long",
                day: "numeric",
                year: "numeric"
            });
        } catch (e) {
            return this.deferDate;
        }
    }

    // ── Cancel enrollment ─────────────────────────────────────────
    async handleCancelEnrollment() {
        if (!confirm("Cancel this campaign? The lead will return to normal tracking.")) return;
        try {
            await cancelEnrollment({ intakeId: this.recordId });
            this.toast("Cancelled", "Campaign cancelled.", "success");
            await this.loadStatus();
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        }
    }

    // ── Defer modal ───────────────────────────────────────────────
    handleOpenDeferModal() {
        this.deferDate = "";
        this.deferError = null;
        this.showDeferModal = true;
    }

    closeDeferModal() {
        this.showDeferModal = false;
    }

    handleQuickSelect(e) {
        const days = parseInt(e.currentTarget.dataset.days, 10);
        const d = new Date();
        d.setDate(d.getDate() + days);
        this.deferDate = d.toISOString().substring(0, 10);
    }

    handleDeferDateChange(e) {
        this.deferDate = e.target.value;
    }

    async handleConfirmDefer() {
        if (!this.deferDate) {
            this.deferError = "Please select a date.";
            return;
        }
        const selected = new Date(this.deferDate + "T12:00:00");
        if (selected <= new Date()) {
            this.deferError = "Please select a future date.";
            return;
        }
        this.isDeferring = true;
        this.deferError = null;
        try {
            await deferIntake({ intakeId: this.recordId, reactivateDateStr: this.deferDate });
            this.showDeferModal = false;
            this.toast("Deferred", `Lead will re-activate on ${this.deferDateLabel}.`, "success");
            await this.loadStatus();
        } catch (e) {
            this.deferError = this.errMsg(e);
        } finally {
            this.isDeferring = false;
        }
    }

    stopProp(e) {
        e.stopPropagation();
    }
    toast(t, m, v) {
        this.dispatchEvent(new ShowToastEvent({ title: t, message: m, variant: v }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}
