import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getIntakeManager from "@salesforce/apex/FirmSettingsController.getIntakeManager";
import saveIntakeManager from "@salesforce/apex/FirmSettingsController.saveIntakeManager";
import searchUsers from "@salesforce/apex/FirmSettingsController.searchUsers";
import getEngagementRules from "@salesforce/apex/FirmSettingsController.getEngagementRules";
import saveEngagementRules from "@salesforce/apex/FirmSettingsController.saveEngagementRules";
import checkDeployStatus from "@salesforce/apex/FirmSettingsController.checkDeployStatus";

const POLL_MS = 2000;
const MAX_POLL = 30;

export default class IntakeFirmSettings extends LightningElement {
    // Manager
    @track currentManager = null;
    @track showUserSearch = false;
    @track userSearchQuery = "";
    @track userSearchResults = [];
    @track isSearching = false;
    @track isSavingManager = false;

    // Engagement rules
    @track rules = {
        warmAfterDays: 1,
        coldAfterDays: 3,
        deadAfterDays: 7,
        escalateAfterDays: 2,
        specialistNotify: true,
        active: true
    };
    @track isRulesLoading = true;
    @track isSavingRules = false;
    @track rulesError = null;

    // Deploy overlay
    @track isDeploying = false;
    @track deployingMsg = "";

    _searchTimer = null;

    async connectedCallback() {
        await Promise.all([this.loadManager(), this.loadRules()]);
    }

    // ── Manager ────────────────────────────────────────────────────
    async loadManager() {
        try {
            this.currentManager = await getIntakeManager();
        } catch (e) {
            console.error("loadManager:", this.errMsg(e));
        }
    }

    get managerInitials() {
        const n = this.currentManager?.name || "";
        return n
            .trim()
            .split(/\s+/)
            .map((p) => p[0] || "")
            .join("")
            .substring(0, 2)
            .toUpperCase();
    }

    handleChangeManager() {
        this.showUserSearch = true;
        this.userSearchResults = [];
        this.userSearchQuery = "";
    }
    cancelUserSearch() {
        this.showUserSearch = false;
    }

    handleUserSearch(e) {
        this.userSearchQuery = e.target.value;
        clearTimeout(this._searchTimer);
        if (!this.userSearchQuery.trim()) {
            this.userSearchResults = [];
            return;
        }
        this._searchTimer = setTimeout(async () => {
            this.isSearching = true;
            try {
                const raw = await searchUsers({ searchTerm: this.userSearchQuery });
                this.userSearchResults = (raw || []).map((u) => ({
                    ...u,
                    initials: u.name
                        .trim()
                        .split(/\s+/)
                        .map((p) => p[0] || "")
                        .join("")
                        .substring(0, 2)
                        .toUpperCase()
                }));
            } catch (e2) {
                console.error(this.errMsg(e2));
            } finally {
                this.isSearching = false;
            }
        }, 350);
    }

    async handleSelectUser(e) {
        const userId = e.currentTarget.dataset.userid;
        const userName = e.currentTarget.dataset.username;
        this.isSavingManager = true;
        this.showUserSearch = false;
        try {
            await saveIntakeManager({ userId });
            await this.loadManager();
            this.toast("Manager Updated", `${userName} is now the Intake Manager.`, "success");
        } catch (e2) {
            this.toast("Error", this.errMsg(e2), "error");
        } finally {
            this.isSavingManager = false;
        }
    }

    // ── Engagement Rules ───────────────────────────────────────────
    async loadRules() {
        this.isRulesLoading = true;
        try {
            const raw = await getEngagementRules();
            this.rules = {
                warmAfterDays: raw.warmAfterDays ?? 1,
                coldAfterDays: raw.coldAfterDays ?? 3,
                deadAfterDays: raw.deadAfterDays ?? 7,
                escalateAfterDays: raw.escalateAfterDays ?? 2,
                specialistNotify: raw.specialistNotify !== false,
                active: raw.active !== false
            };
        } catch (e) {
            this.toast("Error loading rules", this.errMsg(e), "error");
        } finally {
            this.isRulesLoading = false;
        }
    }

    handleRuleChange(e) {
        const field = e.target.dataset.field;
        const val = parseFloat(e.target.value);
        this.rules = { ...this.rules, [field]: isNaN(val) ? 0 : val };
        this.rulesError = null;
    }

    handleRuleToggle(e) {
        const field = e.target.dataset.field;
        this.rules = { ...this.rules, [field]: e.target.checked };
    }

    get saveRulesLabel() {
        return this.isSavingRules ? "Saving…" : "Save Rules";
    }

    async handleSaveRules() {
        const err = this.validateRules();
        if (err) {
            this.rulesError = err;
            return;
        }
        this.isSavingRules = true;
        try {
            const jobId = await saveEngagementRules({ rulesJson: JSON.stringify(this.rules) });
            await this.deployAndPoll(jobId, "Engagement rules saved.", "Saving rules…");
        } catch (e) {
            this.toast("Save Failed", this.errMsg(e), "error");
        } finally {
            this.isSavingRules = false;
        }
    }

    validateRules() {
        const r = this.rules;
        if (r.warmAfterDays < 0) return "Warm threshold cannot be negative.";
        if (r.coldAfterDays <= r.warmAfterDays) return "Cold threshold must be greater than Warm.";
        if (r.deadAfterDays <= r.coldAfterDays) return "Dead threshold must be greater than Cold.";
        if (r.escalateAfterDays < 1) return "Escalation must be at least 1 BH day.";
        return null;
    }

    // ── Deploy polling (same pattern as rule builder) ──────────────
    async deployAndPoll(jobId, successMsg, label) {
        this.isDeploying = true;
        this.deployingMsg = label;
        let polls = 0;
        try {
            while (polls < MAX_POLL) {
                await this._sleep(POLL_MS);
                polls++;
                try {
                    const status = await checkDeployStatus({ jobId });
                    if (status === "Succeeded") {
                        this.toast("Saved", successMsg, "success");
                        return;
                    }
                    this.deployingMsg = `${label} (${polls * (POLL_MS / 1000)}s)`;
                } catch (pollErr) {
                    this.toast("Deploy Failed", this.errMsg(pollErr), "error");
                    return;
                }
            }
            this.toast("Timeout", "Check Setup → Deployment Status.", "warning");
        } finally {
            this.isDeploying = false;
            this.deployingMsg = "";
        }
    }

    _sleep(ms) {
        return new Promise((r) => setTimeout(r, ms));
    }

    toast(t, m, v) {
        this.dispatchEvent(new ShowToastEvent({ title: t, message: m, variant: v }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}