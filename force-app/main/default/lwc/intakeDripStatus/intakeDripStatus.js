import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getEnrollmentStatus from "@salesforce/apex/DripCampaignController.getEnrollmentStatus";
import getActiveCampaigns from "@salesforce/apex/DripCampaignController.getActiveCampaigns";
import deferIntake from "@salesforce/apex/DripCampaignController.deferIntake";
import cancelEnrollment from "@salesforce/apex/DripCampaignController.cancelEnrollment";

export default class IntakeDripStatus extends LightningElement {
    @api recordId;

    @track isLoading = true;
    @track enrollment = { isEnrolled: false };

    // Defer modal
    @track showDeferModal = false;
    @track isCampaignsLoading = false;
    @track campaigns = []; // raw — no selection state stored here
    @track selectedCampaignId = null; // scalar — drives enrichedCampaigns getter
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
        return `width:${this.enrollment?.progressPct || 0}%;`;
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

    get hasActiveCampaigns() {
        return this.campaigns.length > 0;
    }

    // Computed getter pattern — selectedCampaignId is a scalar @track,
    // so reassigning it always triggers this getter to recompute.
    get enrichedCampaigns() {
        return (this.campaigns || []).map((c) => {
            const isSelected = c.id === this.selectedCampaignId;
            const steps = (c.steps || []).map((s, idx) => ({
                ...s,
                previewKey: c.id + "-" + idx,
                icon: s.channel === "Email" ? "✉" : "☎",
                label: s.channel === "Email" ? s.subject : s.taskType + " — " + s.subject
            }));
            return {
                ...c,
                isSelected,
                hasSteps: steps.length > 0,
                steps,
                cardClass: isSelected ? "campaign-select-card campaign-select-card-selected" : "campaign-select-card"
            };
        });
    }

    get confirmDeferDisabled() {
        return this.isDeferring || !this.selectedCampaignId || !this.deferDate;
    }

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

    async handleOpenDeferModal() {
        this.deferDate = "";
        this.deferError = null;
        this.selectedCampaignId = null;
        this.showDeferModal = true;
        this.isCampaignsLoading = true;
        try {
            this.campaigns = (await getActiveCampaigns({ type: "Deferred" })) || [];
        } catch (e) {
            this.campaigns = [];
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isCampaignsLoading = false;
        }
    }

    closeDeferModal() {
        this.showDeferModal = false;
    }

    handleSelectCampaign(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedCampaignId = this.selectedCampaignId === id ? null : id;
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
        if (!this.selectedCampaignId) {
            this.deferError = "Please choose a campaign.";
            return;
        }
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
            await deferIntake({
                intakeId: this.recordId,
                campaignId: this.selectedCampaignId,
                reactivateDateStr: this.deferDate
            });
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