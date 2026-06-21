import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRules from "@salesforce/apex/AssignmentRuleController.getRules";
import getIntakeFields from "@salesforce/apex/AssignmentRuleController.getIntakeFields";
import getQueues from "@salesforce/apex/AssignmentRuleController.getQueues";
import getUsers from "@salesforce/apex/AssignmentRuleController.getUsers";
import saveRule from "@salesforce/apex/AssignmentRuleController.saveRule";
import toggleRule from "@salesforce/apex/AssignmentRuleController.toggleRule";
import reorderRules from "@salesforce/apex/AssignmentRuleController.reorderRules";
import checkDeployStatus from "@salesforce/apex/AssignmentRuleController.checkDeployStatus";

let _uid = 0;
const nextId = () => `cid_${++_uid}`;

const POLL_INTERVAL_MS = 2000;
const MAX_POLLS = 30; // 60 second ceiling before a timeout warning

const OPS = {
    STRING: [
        { label: "Equals", value: "equals" },
        { label: "Not Equals", value: "not_equals" },
        { label: "Contains", value: "contains" },
        { label: "Starts With", value: "starts_with" },
        { label: "Ends With", value: "ends_with" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ],
    TEXTAREA: [
        { label: "Equals", value: "equals" },
        { label: "Not Equals", value: "not_equals" },
        { label: "Contains", value: "contains" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ],
    PICKLIST: [
        { label: "Equals", value: "equals" },
        { label: "Not Equals", value: "not_equals" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ],
    BOOLEAN: [
        { label: "Equals", value: "equals" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ],
    CURRENCY: [
        { label: "Equals", value: "equals" },
        { label: "Not Equals", value: "not_equals" },
        { label: "Greater Than", value: "greater_than" },
        { label: "Less Than", value: "less_than" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ],
    INTEGER: [
        { label: "Equals", value: "equals" },
        { label: "Not Equals", value: "not_equals" },
        { label: "Greater Than", value: "greater_than" },
        { label: "Less Than", value: "less_than" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ],
    DOUBLE: [
        { label: "Equals", value: "equals" },
        { label: "Not Equals", value: "not_equals" },
        { label: "Greater Than", value: "greater_than" },
        { label: "Less Than", value: "less_than" },
        { label: "Is Blank", value: "is_blank" },
        { label: "Is Not Blank", value: "is_not_blank" }
    ]
};
const NO_VAL = new Set(["is_blank", "is_not_blank"]);
const LOGIC_OPTS = [
    { label: "All conditions must match (AND)", value: "AND" },
    { label: "Any condition must match (OR)", value: "OR" }
];
const ASSIGN_OPTS = [
    { label: "Queue", value: "Queue" },
    { label: "User", value: "User" }
];

export default class IntakeAssignmentRuleBuilder extends LightningElement {
    @track rules = [];
    @track editingRule = null;
    @track isLoading = true;
    @track isSaving = false;

    // Deployment overlay state
    @track isDeploying = false;
    @track deployingMsg = "";

    _fields = [];
    _queues = [];
    _users = [];

    async connectedCallback() {
        await this.loadAll();
    }

    async loadAll() {
        this.isLoading = true;
        try {
            const [rawRules, fields, queues, users] = await Promise.all([
                getRules(),
                getIntakeFields(),
                getQueues(),
                getUsers()
            ]);
            this._fields = fields || [];
            this._queues = queues || [];
            this._users = users || [];
            this.rules = (rawRules || []).map((r) => this.buildRule(r));
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    buildRule(r) {
        const conditions = (r.conditions || []).map((c, i) => this.buildCond(c, i));
        return {
            developerName: r.developerName || "",
            label: r.label || "",
            order: r.order || 0,
            isActive: r.isActive !== false,
            assignToType: r.assignToType || "Queue",
            assignToId: r.assignToId || "",
            assignToName: r.assignToName || "",
            conditionLogic: r.conditionLogic || "AND",
            stopOnMatch: r.stopOnMatch === true,
            conditions,
            activeBadgeClass: r.isActive !== false ? "badge badge-on" : "badge badge-off",
            activeLabel: r.isActive !== false ? "Active" : "Inactive",
            targetOptions: this.targetOpts(r.assignToType || "Queue"),
            conditionSummary: this.buildSummary(r)
        };
    }

    buildCond(c, idx) {
        const field = c.fieldApiName || "";
        const op = c.operator || "equals";
        const meta = this._fields.find((f) => f.value === field) || {};
        const type = meta.type || "STRING";
        const pvs = meta.picklistValues || [];
        return {
            tempId: nextId(),
            developerName: c.developerName || "",
            order: c.order || idx + 1,
            displayIndex: idx + 1,
            fieldApiName: field,
            operator: op,
            value: c.value || "",
            operatorOptions: OPS[type] || OPS.STRING,
            showValue: !NO_VAL.has(op),
            isPicklist: type === "PICKLIST" && pvs.length > 0,
            valueOptions: pvs.map((v) => ({ label: v, value: v }))
        };
    }

    targetOpts(type) {
        return type === "User"
            ? this._users.map((u) => ({ label: u.name, value: u.id }))
            : this._queues.map((q) => ({ label: q.name, value: q.id }));
    }

    buildSummary(r) {
        const conds = r.conditions || [];
        if (!conds.length) return "No conditions (catch-all)";
        if (conds.length === 1) {
            const c = conds[0];
            return `${c.fieldApiName || "?"} ${c.operator || "?"}${c.value ? ` "${c.value}"` : ""}`;
        }
        return `${conds.length} conditions [${r.conditionLogic || "AND"}]`;
    }

    // ── Getters ─────────────────────────────────────────────────────
    get fieldOptions() {
        return this._fields.map((f) => ({ label: f.label, value: f.value }));
    }
    get logicOptions() {
        return LOGIC_OPTS;
    }
    get assignTypeOptions() {
        return ASSIGN_OPTS;
    }
    get hasRules() {
        return this.rules.length > 0;
    }
    get showEditor() {
        return this.editingRule !== null;
    }
    get editorTitle() {
        return this.editingRule?.developerName ? `Editing: ${this.editingRule.label}` : "New Rule";
    }
    get saveLabel() {
        return this.isSaving ? "Saving…" : "Save Rule";
    }
    get displayRules() {
        const sel = this.editingRule?.developerName;
        return this.rules.map((r) => ({
            ...r,
            cardClass: "rule-card" + (r.developerName === sel ? " rule-card-selected" : "")
        }));
    }

    // ── Core polling helper ─────────────────────────────────────────
    /**
     * Shows the overlay, polls every 2 s until the deployment finishes,
     * then reloads the rule list and shows the appropriate toast.
     * Never resolves to a blind setTimeout — the UX is always driven by
     * the actual deployment state.
     */
    async deployAndPoll(jobId, successMsg, deployingLabel) {
        this.isDeploying = true;
        this.deployingMsg = deployingLabel || "Saving changes…";
        let polls = 0;
        try {
            while (polls < MAX_POLLS) {
                await this._sleep(POLL_INTERVAL_MS);
                polls++;
                try {
                    const status = await checkDeployStatus({ jobId });
                    if (status === "Succeeded") {
                        await this.loadAll();
                        this.toast("Saved", successMsg, "success");
                        return;
                    }
                    // Pending / InProgress — keep polling, update the counter so user sees progress
                    this.deployingMsg = `${deployingLabel || "Saving changes…"} (${polls * (POLL_INTERVAL_MS / 1000)}s)`;
                } catch (apexErr) {
                    // Apex threw — deployment failed or was cancelled
                    this.toast("Deploy Failed", this.errMsg(apexErr), "error");
                    return;
                }
            }
            // Exceeded max polls — very unlikely but handle gracefully
            this.toast(
                "Still deploying…",
                "The deployment is taking longer than expected. Check Setup → Deployment Status.",
                "warning"
            );
        } finally {
            this.isDeploying = false;
            this.deployingMsg = "";
        }
    }

    _sleep(ms) {
        return new Promise((r) => setTimeout(r, ms));
    }

    // ── Left panel ──────────────────────────────────────────────────
    handleAddRule() {
        this.editingRule = {
            developerName: "",
            label: "",
            order: this.rules.length + 1,
            isActive: true,
            assignToType: "Queue",
            assignToId: "",
            assignToName: "",
            conditionLogic: "AND",
            stopOnMatch: false,
            conditions: [],
            targetOptions: this.targetOpts("Queue"),
            _devNameLocked: false
        };
    }

    handleSelectRule(e) {
        const rule = this.rules.find((r) => r.developerName === e.currentTarget.dataset.devname);
        if (!rule) return;
        this.editingRule = {
            ...rule,
            conditions: rule.conditions.map((c, i) => ({ ...c, tempId: nextId(), displayIndex: i + 1 })),
            targetOptions: this.targetOpts(rule.assignToType),
            _devNameLocked: true
        };
    }

    async handleToggleRule(e) {
        e.stopPropagation();
        const devName = e.currentTarget.dataset.devname;
        const rule = this.rules.find((r) => r.developerName === devName);
        if (!rule) return;
        const toActive = !rule.isActive;
        try {
            const jobId = await toggleRule({ developerName: devName, isActive: toActive });
            await this.deployAndPoll(
                jobId,
                `Rule "${rule.label}" ${toActive ? "activated" : "deactivated"}.`,
                toActive ? "Activating rule…" : "Deactivating rule…"
            );
        } catch (e2) {
            this.toast("Error", this.errMsg(e2), "error");
        }
    }

    async handleReorder(e) {
        e.stopPropagation();
        const devName = e.currentTarget.dataset.devname;
        const dir = e.currentTarget.dataset.dir;
        const arr = [...this.rules];
        const idx = arr.findIndex((r) => r.developerName === devName);
        if (dir === "up" && idx > 0) [arr[idx - 1], arr[idx]] = [arr[idx], arr[idx - 1]];
        else if (dir === "down" && idx < arr.length - 1) [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
        else return;
        arr.forEach((r, i) => (r.order = i + 1));
        this.rules = arr; // optimistic update so the card order shifts immediately
        try {
            const jobId = await reorderRules({ orderedDeveloperNames: arr.map((r) => r.developerName) });
            await this.deployAndPoll(jobId, "Rule order saved.", "Saving order…");
        } catch (e2) {
            this.toast("Error", this.errMsg(e2), "error");
            await this.loadAll(); // revert optimistic update on failure
        }
    }

    stopProp(e) {
        e.stopPropagation();
    }

    // ── Editor: rule-level ──────────────────────────────────────────
    handleRuleFieldChange(e) {
        const fld = e.currentTarget.dataset.fld;
        const val = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
        let patch = { [fld]: val };
        if (fld === "label" && !this.editingRule._devNameLocked) {
            patch.developerName = this.safeDevName(val);
        }
        if (fld === "assignToType") {
            patch.targetOptions = this.targetOpts(val);
            patch.assignToId = "";
            patch.assignToName = "";
        }
        if (fld === "assignToId") {
            const opt = (this.editingRule.targetOptions || []).find((o) => o.value === val);
            patch.assignToName = opt ? opt.label : "";
        }
        this.editingRule = { ...this.editingRule, ...patch };
    }

    // ── Editor: condition-level ─────────────────────────────────────
    handleAddCondition() {
        const cond = this.buildCond({}, this.editingRule.conditions.length);
        this.editingRule = { ...this.editingRule, conditions: [...this.editingRule.conditions, cond] };
    }

    handleRemoveCondition(e) {
        const tid = e.currentTarget.dataset.tempid;
        const conditions = this.editingRule.conditions
            .filter((c) => c.tempId !== tid)
            .map((c, i) => ({ ...c, displayIndex: i + 1, order: i + 1 }));
        this.editingRule = { ...this.editingRule, conditions };
    }

    handleCondChange(e) {
        const tid = e.currentTarget.dataset.tempid;
        const fld = e.currentTarget.dataset.fld;
        const val = e.detail.value;
        const conditions = this.editingRule.conditions.map((c, idx) => {
            if (c.tempId !== tid) return c;
            let next = { ...c, [fld]: val };
            if (fld === "fieldApiName") {
                const meta = this._fields.find((f) => f.value === val) || {};
                const type = meta.type || "STRING";
                const pvs = meta.picklistValues || [];
                next.operatorOptions = OPS[type] || OPS.STRING;
                next.operator = "equals";
                next.value = "";
                next.showValue = true;
                next.isPicklist = type === "PICKLIST" && pvs.length > 0;
                next.valueOptions = pvs.map((v) => ({ label: v, value: v }));
            }
            if (fld === "operator") {
                next.showValue = !NO_VAL.has(val);
                if (!next.showValue) next.value = "";
            }
            return next;
        });
        this.editingRule = { ...this.editingRule, conditions };
    }

    // ── Save ────────────────────────────────────────────────────────
    async handleSaveRule() {
        const err = this.validate();
        if (err) {
            this.toast("Validation", err, "warning");
            return;
        }
        this.isSaving = true;
        const payload = {
            ...this.editingRule,
            conditions: this.editingRule.conditions.map(
                (
                    {
                        tempId,
                        operatorOptions,
                        showValue,
                        isPicklist,
                        valueOptions,
                        displayIndex,
                        activeBadgeClass,
                        activeLabel,
                        targetOptions,
                        conditionSummary,
                        cardClass,
                        ...rest
                    },
                    i
                ) => ({ ...rest, order: i + 1 })
            )
        };
        delete payload.activeBadgeClass;
        delete payload.activeLabel;
        delete payload.targetOptions;
        delete payload.conditionSummary;
        delete payload.cardClass;
        delete payload._devNameLocked;
        try {
            const jobId = await saveRule({ ruleJson: JSON.stringify(payload) });
            this.editingRule = null; // close the editor immediately
            await this.deployAndPoll(jobId, `Rule "${payload.label}" saved successfully.`, "Saving rule…");
        } catch (e) {
            this.toast("Save Failed", this.errMsg(e), "error");
        } finally {
            this.isSaving = false;
        }
    }

    handleCancelEdit() {
        this.editingRule = null;
    }

    validate() {
        const r = this.editingRule;
        if (!r.label?.trim()) return "Rule name is required.";
        if (!r.assignToId) return "Select a target queue or user.";
        if (!r._devNameLocked) {
            const taken = this.rules.some((ex) => ex.developerName === r.developerName);
            if (taken) return `Developer name "${r.developerName}" is already taken. Use a different rule name.`;
        }
        for (const c of r.conditions) {
            if (!c.fieldApiName || !c.operator) return "Each condition needs a field and operator.";
            if (c.showValue && !c.value?.trim()) return "A condition is missing its value.";
        }
        return null;
    }

    safeDevName(label) {
        let dn = label.replace(/\s+/g, "_").replace(/[^a-zA-Z0-9_]/g, "");
        if (/^[0-9]/.test(dn)) dn = "Rule_" + dn;
        return (dn || "New_Rule").substring(0, 40);
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}