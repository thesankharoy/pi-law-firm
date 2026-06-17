import { LightningElement, track, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getMyStatus from "@salesforce/apex/UserAvailabilityService.getMyStatus";
import setStatus from "@salesforce/apex/UserAvailabilityService.setStatus";
import heartbeat from "@salesforce/apex/UserAvailabilityService.heartbeat";
import getOpenIntakes from "@salesforce/apex/UserAvailabilityService.getOpenIntakes";

const HEARTBEAT_INTERVAL = 60 * 1000 * 5; // 5 minute
const INTAKE_POLL_INTERVAL = 15 * 1000; // 15 seconds — live intake list

function statusClass(status) {
    if (!status) return "intake-status-badge";
    switch (status.toLowerCase()) {
        case "new":
            return "intake-status-badge status-new";
        case "working":
            return "intake-status-badge status-working";
        default:
            return "intake-status-badge status-other";
    }
}

export default class IntakeAvailabilityToggle extends NavigationMixin(LightningElement) {
    @api label = "My Availability";
    @track specialistData = null;
    @track openIntakes = [];
    @track isLoading = false;
    @track errorMessage = null;
    @track lastRefreshed = "—";

    _heartbeatTimer = null;
    _intakePollTimer = null;
    _statusPollTimer = null;

    connectedCallback() {
        this.loadStatus();
        this.loadOpenIntakes();
        this._heartbeatTimer = setInterval(() => this.sendHeartbeat(), HEARTBEAT_INTERVAL);
        this._intakePollTimer = setInterval(() => this.loadOpenIntakes(), INTAKE_POLL_INTERVAL);
        this._statusPollTimer = setInterval(() => this.loadStatus(), 60000);
    }

    disconnectedCallback() {
        clearInterval(this._heartbeatTimer);
        clearInterval(this._intakePollTimer);
        clearInterval(this._statusPollTimer);
    }

    async loadStatus() {
        try {
            this.specialistData = await getMyStatus();
            this.errorMessage = null;
        } catch (e) {
            // Show the actual Apex error so you can diagnose it
            this.errorMessage = e?.body?.message || e?.message || "Could not load status.";
        }
    }

    async loadOpenIntakes() {
        try {
            const raw = await getOpenIntakes();
            this.openIntakes = (raw || []).map((i) => ({
                ...i,
                statusClass: statusClass(i.status)
            }));
            const now = new Date();
            this.lastRefreshed = now.toLocaleTimeString([], {
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit"
            });
        } catch (e) {
            // Previously silent — now surfaces the error so you can see it
            console.error("getOpenIntakes failed:", e?.body?.message || e?.message);
            // Don't overwrite the list on transient errors — keep showing stale data
            const now = new Date();
            this.lastRefreshed =
                now.toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                    second: "2-digit"
                }) + " (refresh failed)";
        }
    }

    async sendHeartbeat() {
        if (this.isActive) {
            try {
                await heartbeat();
            } catch (e) {
                // Show the actual Apex error so you can diagnose it
                this.errorMessage = e?.body?.message || e?.message || "Failed to send heartbeat.";
            }
        }
    }

    async handleGoActive() {
        await this.updateStatus("Active");
    }
    async handleGoInactive() {
        await this.updateStatus("Inactive");
    }
    async handleOnBreak() {
        await this.updateStatus("On Break");
    }

    async updateStatus(newStatus) {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            this.specialistData = await setStatus({ newStatus });
            // Immediately refresh intakes — draining may have just assigned new ones
            await this.loadOpenIntakes();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Status Updated",
                    message: `You are now ${newStatus}`,
                    variant: newStatus === "Active" ? "success" : "warning",
                    mode: "dismissable"
                })
            );
        } catch (e) {
            // Show the actual Apex error so you can diagnose it
            this.errorMessage = e?.body?.message || e?.message || "Failed to update status.";
        } finally {
            this.isLoading = false;
        }
    }

    handleIntakeClick(e) {
        const id = e.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: "standard__recordPage",
            attributes: { recordId: id, objectApiName: "Intake__c", actionName: "view" }
        });
    }

    // ── Getters ────────────────────────────────────────────────
    get isActive() {
        return this.specialistData?.isActive === true;
    }
    get currentStatus() {
        return this.specialistData?.status || "Loading...";
    }
    get openIntakesCount() {
        return this.openIntakes?.length || 0;
    }
    get hasOpenIntakes() {
        return this.openIntakesCount > 0;
    }

    get statusBadgeClass() {
        const s = this.specialistData?.status;
        if (s === "Active") return "badge badge-active";
        if (s === "On Break") return "badge badge-break";
        return "badge badge-inactive";
    }

    get capacityPercent() {
        const max = this.specialistData?.maxCapacity || 1;
        const active = this.specialistData?.activeCount || 0;
        return Math.min(100, Math.round((active / max) * 100));
    }

    get capacityBarStyle() {
        const pct = this.capacityPercent;
        const color = pct >= 90 ? "#c62828" : pct >= 70 ? "#e65100" : "#1b5e20";
        return `width:${pct}%;background:${color};transition:width 0.4s ease;`;
    }
}
