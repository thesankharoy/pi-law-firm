import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getCampaigns from "@salesforce/apex/DripCampaignController.getCampaigns";
import saveCampaign from "@salesforce/apex/DripCampaignController.saveCampaign";
import deleteCampaign from "@salesforce/apex/DripCampaignController.deleteCampaign";
import toggleCampaignActive from "@salesforce/apex/DripCampaignController.toggleCampaignActive";
import getSteps from "@salesforce/apex/DripCampaignController.getSteps";
import saveStep from "@salesforce/apex/DripCampaignController.saveStep";
import deleteStep from "@salesforce/apex/DripCampaignController.deleteStep";

const MERGE_FIELDS = [
    { token: "{ClientFirstName}", label: "First Name", display: "{ClientFirstName}" },
    { token: "{ClientFullName}", label: "Full Name", display: "{ClientFullName}" },
    { token: "{IntakeName}", label: "Intake #", display: "{IntakeName}" },
    { token: "{SpecialistName}", label: "Specialist", display: "{SpecialistName}" },
    { token: "{IncidentType}", label: "Incident", display: "{IncidentType}" }
];

export default class IntakeDripManager extends LightningElement {
    // Segment tabs — completely separate views, separate type
    @track activeTab = "deferred"; // 'deferred' | 'reactivation'

    // View
    @track currentView = "list"; // 'list' | 'detail'
    @track selectedCampaign = null;

    // Data
    @track campaigns = [];
    @track steps = [];
    @track isLoading = true;
    @track isStepsLoading = false;

    // Campaign modal
    @track showCampaignModal = false;
    @track campaignForm = { name: "", totalDays: 90, description: "", id: null };
    @track campaignFormError = null;
    @track isSavingCampaign = false;

    // Step modal
    @track showStepModal = false;
    @track stepForm = { id: null, dayNumber: 1, channel: "Email", subject: "", body: "", taskType: "Call" };
    @track stepFormError = null;
    @track isSavingStep = false;

    _needsTextareaSync = false;
    _pendingCursor = null;

    get mergeFields() {
        return MERGE_FIELDS;
    }

    async connectedCallback() {
        await this.loadCampaigns();
    }

    renderedCallback() {
        if (this._needsTextareaSync && this.showStepModal) {
            const ta = this.template.querySelector('textarea[data-field="body"]');
            if (ta) {
                ta.value = this.stepForm.body || "";
                this._needsTextareaSync = false;
            }
        }
        if (this._pendingCursor) {
            const { field, pos } = this._pendingCursor;
            const el = this.template.querySelector(`input[data-field="${field}"], textarea[data-field="${field}"]`);
            if (el) {
                el.setSelectionRange(pos, pos);
                el.focus();
            }
            this._pendingCursor = null;
        }
    }

    // ── Tab switching ───────────────────────────────────────────────
    get isDeferredTab() {
        return this.activeTab === "deferred";
    }
    get isReactivationTab() {
        return this.activeTab === "reactivation";
    }
    get deferredTabClass() {
        return this.isDeferredTab ? "segment-tab segment-tab-active" : "segment-tab";
    }
    get reactivationTabClass() {
        return this.isReactivationTab ? "segment-tab segment-tab-active" : "segment-tab";
    }

    async handleTabSwitch(e) {
        const tab = e.currentTarget.dataset.tab;
        if (tab === this.activeTab) return;
        this.activeTab = tab;
        await this.loadCampaigns();
    }

    get currentType() {
        return this.isDeferredTab ? "Deferred" : "Re-activation";
    }

    get emptyStateTitle() {
        return this.isDeferredTab ? "No Deferred campaigns yet" : "No Re-activation campaigns yet";
    }
    get emptyStateDesc() {
        return this.isDeferredTab
            ? 'Build a campaign specialists can choose from when they defer a "call me later" lead.'
            : "Build the single campaign that automatically re-engages leads once they go Dead.";
    }

    get detailTypeBadgeClass() {
        return this.isDeferredTab ? "type-badge badge-deferred" : "type-badge badge-reactivation";
    }

    // ── Data loading ─────────────────────────────────────────────
    async loadCampaigns() {
        this.isLoading = true;
        try {
            const raw = await getCampaigns({ type: this.currentType });
            this.campaigns = (raw || []).map((c) => ({
                ...c,
                barStyle: this.isDeferredTab ? "background:#2563eb;" : "background:#7c3aed;",
                cardClass: c.isActive ? "camp-card" : "camp-card camp-card-inactive",
                toggleLabel: c.isActive
                    ? this.isReactivationTab
                        ? "Active — the one auto-enrolling Dead leads"
                        : "Active — click to deactivate"
                    : "Inactive — click to activate"
            }));
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    async loadSteps(campaignId) {
        this.isStepsLoading = true;
        try {
            const raw = await getSteps({ campaignId });
            this.steps = (raw || []).map((s) => ({
                ...s,
                channelBadgeClass: s.channel === "Email" ? "channel-badge badge-email" : "channel-badge badge-task",
                showTaskType: s.channel === "Specialist Task" && !!s.taskType,
                bodyPreview: s.body ? s.body.substring(0, 80) + (s.body.length > 80 ? "…" : "") : ""
            }));
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isStepsLoading = false;
        }
    }

    // ── Navigation ─────────────────────────────────────────────────
    get isDetailView() {
        return this.currentView === "detail";
    }
    get hasCampaigns() {
        return this.campaigns.length > 0;
    }
    get hasSteps() {
        return this.steps.length > 0;
    }

    async handleViewSteps(e) {
        const id = e.currentTarget.dataset.id;
        this.selectedCampaign = this.campaigns.find((c) => c.id === id) || null;
        if (!this.selectedCampaign) return;
        this.currentView = "detail";
        await this.loadSteps(id);
    }

    handleBackToList() {
        this.currentView = "list";
        this.selectedCampaign = null;
        this.steps = [];
    }

    // ── Campaign CRUD ──────────────────────────────────────────────
    get campaignModalTitle() {
        return this.campaignForm.id ? "Edit Campaign" : "New Campaign";
    }
    get saveCampaignLabel() {
        return this.isSavingCampaign ? "Saving…" : "Save";
    }

    handleNewCampaign() {
        this.campaignForm = { name: "", totalDays: 90, description: "", id: null };
        this.campaignFormError = null;
        this.showCampaignModal = true;
    }

    handleEditCampaign(e) {
        const id = e.currentTarget.dataset.id;
        const c = this.campaigns.find((x) => x.id === id);
        if (!c) return;
        this.campaignForm = {
            name: c.name,
            totalDays: c.totalDays,
            description: c.description || "",
            id: c.id
        };
        this.campaignFormError = null;
        this.showCampaignModal = true;
    }

    handleCampaignFormInput(e) {
        const f = e.target.dataset.field;
        this.campaignForm = { ...this.campaignForm, [f]: e.target.value };
    }

    async handleSaveCampaign() {
        if (!this.campaignForm.name?.trim()) {
            this.campaignFormError = "Campaign name is required.";
            return;
        }
        if (this.isReactivationTab && (!this.campaignForm.totalDays || this.campaignForm.totalDays < 1)) {
            this.campaignFormError = "Duration must be at least 1 day.";
            return;
        }
        this.isSavingCampaign = true;
        try {
            await saveCampaign({
                campaignJson: JSON.stringify({
                    ...this.campaignForm,
                    type: this.currentType,
                    isActive: true // newly created/edited campaigns activate by default
                })
            });
            this.showCampaignModal = false;
            await this.loadCampaigns();
            this.toast("Saved", "Campaign saved.", "success");
        } catch (e) {
            this.campaignFormError = this.errMsg(e);
        } finally {
            this.isSavingCampaign = false;
        }
    }

    async handleDeleteCampaign(e) {
        const id = e.currentTarget.dataset.id;
        const c = this.campaigns.find((x) => x.id === id);
        // eslint-disable-next-line no-alert
        if (!confirm(`Delete campaign "${c?.name}"? All steps will also be deleted.`)) return;
        try {
            await deleteCampaign({ campaignId: id });
            await this.loadCampaigns();
            this.toast("Deleted", "Campaign deleted.", "success");
        } catch (ex) {
            this.toast("Error", this.errMsg(ex), "error");
        }
    }

    // Reload the full list after toggling — for Re-activation, the
    // server may have silently deactivated a sibling campaign.
    async handleToggleActive(e) {
        const id = e.target.dataset.id;
        const isActive = e.target.checked;
        try {
            await toggleCampaignActive({ campaignId: id, isActive });
            await this.loadCampaigns();
        } catch (ex) {
            this.toast("Error", this.errMsg(ex), "error");
            await this.loadCampaigns();
        }
    }

    closeCampaignModal() {
        this.showCampaignModal = false;
    }

    // ── Step CRUD ──────────────────────────────────────────────────
    get stepModalTitle() {
        return this.stepForm.id ? "Edit Step" : "New Step";
    }
    get saveStepLabel() {
        return this.isSavingStep ? "Saving…" : "Save Step";
    }
    get showTaskType() {
        return this.stepForm.channel === "Specialist Task";
    }
    get emailChannelClass() {
        return this.stepForm.channel === "Email" ? "type-toggle-btn selected" : "type-toggle-btn";
    }
    get taskChannelClass() {
        return this.stepForm.channel === "Specialist Task" ? "type-toggle-btn selected" : "type-toggle-btn";
    }
    get taskTypeIsCall() {
        return this.stepForm.taskType === "Call";
    }
    get taskTypeIsEmail() {
        return this.stepForm.taskType === "Email";
    }
    get taskTypeIsSms() {
        return this.stepForm.taskType === "SMS";
    }

    get dayNumberHint() {
        return this.isDeferredTab
            ? "All steps in a Deferred campaign fire together on the date the specialist picks"
            : "Days since the lead went Dead and entered this campaign";
    }

    handleNewStep() {
        const defaultDay = this.isDeferredTab ? 0 : 7;
        this.stepForm = { id: null, dayNumber: defaultDay, channel: "Email", subject: "", body: "", taskType: "Call" };
        this.stepFormError = null;
        this._needsTextareaSync = true;
        this.showStepModal = true;
    }

    handleEditStep(e) {
        const id = e.currentTarget.dataset.id;
        const s = this.steps.find((x) => x.id === id);
        if (!s) return;
        this.stepForm = {
            id: s.id,
            dayNumber: s.dayNumber,
            channel: s.channel,
            subject: s.subject || "",
            body: s.body || "",
            taskType: s.taskType || "Call",
            sortOrder: s.sortOrder || 0
        };
        this.stepFormError = null;
        this._needsTextareaSync = true;
        this.showStepModal = true;
    }

    handleChannelSelect(e) {
        this.stepForm = { ...this.stepForm, channel: e.currentTarget.dataset.channel };
    }
    handleStepFormInput(e) {
        const f = e.target.dataset.field;
        this.stepForm = { ...this.stepForm, [f]: e.target.value };
    }
    handleStepFormSelect(e) {
        const f = e.target.dataset.field;
        this.stepForm = { ...this.stepForm, [f]: e.target.value };
    }
    handleBodyInput(e) {
        this.stepForm = { ...this.stepForm, body: e.target.value };
    }

    handleInsertMergeField(e) {
        const field = e.currentTarget.dataset.field;
        const token = e.currentTarget.dataset.token;
        const el = this.template.querySelector(`input[data-field="${field}"], textarea[data-field="${field}"]`);
        const current = field === "subject" ? this.stepForm.subject || "" : this.stepForm.body || "";
        const start = el ? el.selectionStart : current.length;
        const end = el ? el.selectionEnd : current.length;
        const newVal = current.substring(0, start) + token + current.substring(end);
        this.stepForm = { ...this.stepForm, [field]: newVal };
        this._pendingCursor = { field, pos: start + token.length };
        if (field === "body") this._needsTextareaSync = true;
    }

    async handleSaveStep() {
        if (!this.stepForm.subject?.trim()) {
            this.stepFormError = "Subject is required.";
            return;
        }
        if (this.stepForm.dayNumber == null || this.stepForm.dayNumber < 0) {
            this.stepFormError = "Day number cannot be negative.";
            return;
        }
        this.isSavingStep = true;
        try {
            await saveStep({ campaignId: this.selectedCampaign.id, stepJson: JSON.stringify(this.stepForm) });
            this.showStepModal = false;
            await this.loadSteps(this.selectedCampaign.id);
            this.toast("Saved", "Step saved.", "success");
        } catch (e) {
            this.stepFormError = this.errMsg(e);
        } finally {
            this.isSavingStep = false;
        }
    }

    async handleDeleteStep(e) {
        const id = e.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        if (!confirm("Delete this step?")) return;
        try {
            await deleteStep({ stepId: id });
            await this.loadSteps(this.selectedCampaign.id);
            this.toast("Deleted", "Step deleted.", "success");
        } catch (ex) {
            this.toast("Error", this.errMsg(ex), "error");
        }
    }

    closeStepModal() {
        this.showStepModal = false;
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