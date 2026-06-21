import { LightningElement, track, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getMyStatus from "@salesforce/apex/UserAvailabilityService.getMyStatus";
import setStatus from "@salesforce/apex/UserAvailabilityService.setStatus";
import heartbeat from "@salesforce/apex/UserAvailabilityService.heartbeat";
import getOpenIntakes from "@salesforce/apex/UserAvailabilityService.getOpenIntakes";

const HEARTBEAT_MS = 5 * 60 * 1000; // 5 minutes
const INTAKE_POLL_MS = 15 * 1000; // 15 seconds
const STATUS_POLL_MS = 60 * 1000; // 1 minute

// Status → colour mapping used in legend, left bar, and badge
const STATUS_META = {
    New: { color: "#22c55e", short: "New", text: "#14532d" },
    Assigned: { color: "#3b82f6", short: "Assigned", text: "#1e3a8a" },
    Working: { color: "#3b82f6", short: "Working", text: "#1e3a8a" },
    "Under Review": { color: "#eab308", short: "Under review", text: "#713f12" },
    Qualified: { color: "#8b5cf6", short: "Qualified", text: "#4c1d95" },
    "Retainer Agreement Sent": { color: "#f97316", short: "Retainer sent", text: "#7c2d12" },
    "Retainer Agreement Signed": { color: "#10b981", short: "Signed", text: "#064e3b" },
    "Turned Down": { color: "#ef4444", short: "Turned down", text: "#7f1d1d" },
    "Referred Out": { color: "#94a3b8", short: "Referred", text: "#374151" },
    Converted: { color: "#14b8a6", short: "Converted", text: "#134e4a" }
};
const DEFAULT_COLOR = "#94a3b8";

function colorFor(status) {
    return (STATUS_META[status] || {}).color || DEFAULT_COLOR;
}
function textFor(status) {
    return (STATUS_META[status] || {}).text || "#374151";
}
function shortFor(status) {
    return (STATUS_META[status] || {}).short || status;
}

export default class IntakeAvailabilityToggle extends NavigationMixin(LightningElement) {
    @api label;

    @track specialistData = null;
    @track openIntakes = [];
    @track isLoading = false;
    @track errorMessage = null;
    @track lastRefreshed = "—";
    @track isInitialLoad = true; // first-load gate
    @track isIntakesLoading = true; // intakes list gate

    _heartbeatTimer = null;
    _intakePollTimer = null;
    _statusPollTimer = null;

    connectedCallback() {
        this.loadStatus();
        this.loadOpenIntakes();
        this._heartbeatTimer = setInterval(() => this.sendHeartbeat(), HEARTBEAT_MS);
        this._intakePollTimer = setInterval(() => this.loadOpenIntakes(), INTAKE_POLL_MS);
        this._statusPollTimer = setInterval(() => this.loadStatus(), STATUS_POLL_MS);
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
            this.errorMessage = e?.body?.message || e?.message || "Could not load status.";
        } finally {
            this.isInitialLoad = false; // always clear initial load gate
        }
    }

    async loadOpenIntakes() {
        try {
            const raw = await getOpenIntakes();
            this.openIntakes = (raw || []).map((i) => {
                const color = colorFor(i.status);
                const text = textFor(i.status);
                return {
                    ...i,
                    barStyle: `background:${color};`,
                    badgeStyle: `background:${color}22;color:${text};border:1px solid ${color}55;`
                };
            });
            const now = new Date();
            this.lastRefreshed = now.toLocaleTimeString([], {
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit"
            });
        } catch (e) {
            console.error("getOpenIntakes failed:", e?.body?.message || e?.message);
            const now = new Date();
            this.lastRefreshed =
                now.toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                    second: "2-digit"
                }) + " (refresh failed)";
        } finally {
            this.isIntakesLoading = false; // always clear on first load
        }
    }

    async sendHeartbeat() {
        if (!this.isActive) return;
        try {
            await heartbeat();
        } catch (e) {
            /* silent */
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

    // ── Getters ───────────────────────────────────────────────────────
    get isActive() {
        return this.specialistData?.isActive === true;
    }
    get openIntakesCount() {
        return this.openIntakes?.length || 0;
    }
    get hasOpenIntakes() {
        return this.openIntakesCount > 0;
    }
    get currentStatus() {
        return this.specialistData?.status || "Loading...";
    }
    get userPhotoUrl() {
        return this.specialistData?.photoUrl || null;
    }
    get hasPhoto() {
        return !!this.userPhotoUrl;
    }

    get userInitials() {
        const name = this.specialistData?.userName || "";
        return (
            name
                .trim()
                .split(/\s+/)
                .map((p) => p[0] || "")
                .join("")
                .substring(0, 2)
                .toUpperCase() || "??"
        );
    }

    get statusBadgeClass() {
        const s = this.specialistData?.status;
        if (s === "Active") return "status-pill pill-active";
        if (s === "On Break") return "status-pill pill-break";
        return "status-pill pill-inactive";
    }

    get isOverCapacity() {
        const max = this.specialistData?.maxCapacity || 0;
        const active = this.specialistData?.activeCount || 0;
        return active > max;
    }

    get overBy() {
        const max = this.specialistData?.maxCapacity || 0;
        const active = this.specialistData?.activeCount || 0;
        return Math.max(0, active - max);
    }

    get overByDisplay() {
        const ob = this.overBy;
        return ob > 0 ? `+${ob}` : "—";
    }
    get overByBoxClass() {
        return this.isOverCapacity ? "stat-box stat-box-alert" : "stat-box";
    }
    get overByValClass() {
        return this.isOverCapacity ? "stat-val stat-val-alert" : "stat-val";
    }

    get capNumberClass() {
        return this.isOverCapacity ? "cap-number cap-number-alert" : "cap-number";
    }

    get capacityArcStyle() {
        if (!this.specialistData) return "";
        const max = this.specialistData.maxCapacity || 1;
        const active = this.specialistData.activeCount || 0;
        const pct = Math.min(active / max, 1);
        const circ = 2 * Math.PI * 46;
        const offset = circ * (1 - pct);
        const color = active > max ? "#ef4444" : active / max >= 0.7 ? "#f97316" : "#22c55e";
        return `stroke-dasharray:${circ.toFixed(1)};stroke-dashoffset:${offset.toFixed(1)};stroke:${color};`;
    }

    get statusCountItems() {
        const counts = {};
        (this.openIntakes || []).forEach((i) => {
            if (i.status) counts[i.status] = (counts[i.status] || 0) + 1;
        });
        return Object.keys(counts).map((status) => ({
            status,
            label: shortFor(status),
            count: counts[status],
            dotStyle: `background:${colorFor(status)};`
        }));
    }

    get statusCountsRow1() {
        return this.statusCountItems.slice(0, 4);
    }
    get statusCountsRow2() {
        return this.statusCountItems.slice(4);
    }
    get hasStatusCounts() {
        return this.statusCountItems.length > 0;
    }
    get hasStatusCountsRow2() {
        return this.statusCountItems.length > 4;
    }
}
