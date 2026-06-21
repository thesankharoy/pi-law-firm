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

const POLL_MS = 2000;
const MAX_POLL = 30;

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

export default class IntakeAssignmentRuleBuilder extends LightningElement {
    @track rules = [];
    @track editingRule = null;
    @track isLoading = true;
    @track isSaving = false;
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
            this.toast("Error loading rules", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    buildRule(r) {
        const conditions = (r.conditions || []).map((c, i) => this.buildCond(c, i));
        const count = conditions.length;
        const logic = r.conditionLogic || "AND";
        return {
            developerName: r.developerName || "",
            label: r.label || "",
            order: r.order || 0,
            isActive: r.isActive !== false,
            assignToType: r.assignToType || "Queue",
            assignToId: r.assignToId || "",
            assignToName: r.assignToName || "",
            conditionLogic: logic,
            stopOnMatch: r.stopOnMatch === true,
            conditions,
            // display props
            activeLabel: r.isActive !== false ? "Active" : "Inactive",
            activePillClass: r.isActive !== false ? "active-pill on" : "active-pill off",
            orderBadgeClass: r.isActive !== false ? "order-badge active" : "order-badge inactive",
            conditionCountText:
                count === 0 ? "No conditions (catch-all)" : count === 1 ? "1 condition" : `${count} conditions`,
            showLogicBadge: count > 1,
            logicBadge: logic,
            logicBadgeClass: logic === "AND" ? "logic-badge and" : "logic-badge or",
            targetOptions: this.targetOpts(r.assignToType || "Queue"),
            _lastEditedLabel: "",
            _devNameLocked: true
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

    // ── Getters ──────────────────────────────────────────────────────
    get hasRules() {
        return this.rules.length > 0;
    }
    get showEditor() {
        return this.editingRule !== null;
    }
    get logicOptions() {
        return LOGIC_OPTS;
    }
    get fieldOptions() {
        return this._fields.map((f) => ({ label: f.label, value: f.value }));
    }
    get saveLabel() {
        return this.isSaving ? "Saving…" : "Save Rule";
    }

    get activeRulesCount() {
        return this.rules.filter((r) => r.isActive).length;
    }
    get rulesStatLabel() {
        if (!this.hasRules) return "No rules yet";
        return `${this.activeRulesCount} active · ${this.rules.length} rules`;
    }
    get statDotClass() {
        return this.activeRulesCount > 0 ? "stat-dot has-active" : "stat-dot no-active";
    }
    get activeToggleLabel() {
        return this.editingRule?.isActive ? "Active · On" : "Active · Off";
    }
    get queueBtnClass() {
        return this.editingRule?.assignToType === "Queue" ? "type-btn selected" : "type-btn";
    }
    get userBtnClass() {
        return this.editingRule?.assignToType === "User" ? "type-btn selected" : "type-btn";
    }
    get editingConditionLogicLabel() {
        const logic = this.editingRule?.conditionLogic || "AND";
        const count = this.editingRule?.conditions?.length || 0;
        if (!count) return "No conditions";
        return logic === "AND" ? "All conditions (AND)" : "Any condition (OR)";
    }
    get editingConditionCount() {
        return this.editingRule?.conditions?.length || 0;
    }
    get displayRules() {
        const sel = this.editingRule?.developerName;
        return this.rules.map((r) => ({
            ...r,
            cardClass: "rule-card" + (r.developerName === sel ? " selected" : "")
        }));
    }

    // ── renderedCallback: sync native select values ───────────────────
    renderedCallback() {
        if (!this.editingRule) return;

        const syncSel = (selector, value) => {
            const el = this.template.querySelector(selector);
            if (el && el.value !== value) el.value = value || "";
        };

        syncSel('select[data-fld="assignToId"]', this.editingRule.assignToId || "");
        syncSel('select[data-fld="conditionLogic"]', this.editingRule.conditionLogic || "AND");

        (this.editingRule.conditions || []).forEach((cond) => {
            // Field select: no data-fld attribute
            const fieldSel = this.template.querySelector(`select[data-tempid="${cond.tempId}"]:not([data-fld])`);
            if (fieldSel) fieldSel.value = cond.fieldApiName || "";

            const opSel = this.template.querySelector(`select[data-tempid="${cond.tempId}"][data-fld="operator"]`);
            if (opSel) opSel.value = cond.operator || "equals";

            if (cond.isPicklist) {
                const valSel = this.template.querySelector(`select[data-tempid="${cond.tempId}"][data-fld="value"]`);
                if (valSel) valSel.value = cond.value || "";
            }
        });
    }

    // ── Left panel ────────────────────────────────────────────────────
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
            activeLabel: "Active",
            activePillClass: "active-pill on",
            _devNameLocked: false,
            _lastEditedLabel: ""
        };
    }

    handleSelectRule(e) {
        const rule = this.rules.find((r) => r.developerName === e.currentTarget.dataset.devname);
        if (!rule) return;
        this.editingRule = {
            ...rule,
            conditions: rule.conditions.map((c, i) => ({ ...c, tempId: nextId(), displayIndex: i + 1 })),
            targetOptions: this.targetOpts(rule.assignToType),
            _devNameLocked: true,
            _lastEditedLabel: ""
        };
    }

    async handleTogglePill(e) {
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
        this.rules = arr;
        try {
            const jobId = await reorderRules({ orderedDeveloperNames: arr.map((r) => r.developerName) });
            await this.deployAndPoll(jobId, "Rule order saved.", "Saving order…");
        } catch (e2) {
            this.toast("Error", this.errMsg(e2), "error");
            await this.loadAll();
        }
    }

    stopProp(e) {
        e.stopPropagation();
    }

    // ── Editor: rule-level native element handlers ────────────────────
    handleInputChange(e) {
        const fld = e.target.dataset.fld;
        const val = e.target.value;
        let patch = { [fld]: val, _lastEditedLabel: "Last edited just now" };
        if (fld === "label" && !this.editingRule._devNameLocked) {
            patch.developerName = this.safeDevName(val);
        }
        this.editingRule = { ...this.editingRule, ...patch };
    }

    handleCheckboxChange(e) {
        const fld = e.target.dataset.fld;
        this.editingRule = {
            ...this.editingRule,
            [fld]: e.target.checked,
            _lastEditedLabel: "Last edited just now"
        };
    }

    handleTypeToggle(e) {
        const type = e.currentTarget.dataset.type;
        this.editingRule = {
            ...this.editingRule,
            assignToType: type,
            targetOptions: this.targetOpts(type),
            assignToId: "",
            assignToName: "",
            _lastEditedLabel: "Last edited just now"
        };
    }

    handleSelectChange(e) {
        const fld = e.target.dataset.fld;
        const val = e.target.value;
        let patch = { [fld]: val, _lastEditedLabel: "Last edited just now" };
        if (fld === "assignToId") {
            const opt = (this.editingRule.targetOptions || []).find((o) => o.value === val);
            patch.assignToName = opt ? opt.label : "";
        }
        this.editingRule = { ...this.editingRule, ...patch };
    }

    // ── Editor: condition-level handlers ─────────────────────────────
    handleAddCondition() {
        const cond = this.buildCond({}, this.editingRule.conditions.length);
        this.editingRule = {
            ...this.editingRule,
            conditions: [...this.editingRule.conditions, cond],
            _lastEditedLabel: "Last edited just now"
        };
    }

    handleRemoveCondition(e) {
        const tid = e.currentTarget.dataset.tempid;
        const conditions = this.editingRule.conditions
            .filter((c) => c.tempId !== tid)
            .map((c, i) => ({ ...c, displayIndex: i + 1, order: i + 1 }));
        this.editingRule = { ...this.editingRule, conditions, _lastEditedLabel: "Last edited just now" };
    }

    handleFieldSelectChange(e) {
        const tid = e.target.dataset.tempid;
        const val = e.target.value;
        const conditions = this.editingRule.conditions.map((c, idx) => {
            if (c.tempId !== tid) return c;
            const meta = this._fields.find((f) => f.value === val) || {};
            const type = meta.type || "STRING";
            const pvs = meta.picklistValues || [];
            return {
                ...c,
                fieldApiName: val,
                operator: "equals",
                value: "",
                operatorOptions: OPS[type] || OPS.STRING,
                showValue: true,
                isPicklist: type === "PICKLIST" && pvs.length > 0,
                valueOptions: pvs.map((v) => ({ label: v, value: v }))
            };
        });
        this.editingRule = { ...this.editingRule, conditions, _lastEditedLabel: "Last edited just now" };
    }

    handleCondSelectChange(e) {
        const tid = e.target.dataset.tempid;
        const fld = e.target.dataset.fld;
        const val = e.target.value;
        const conditions = this.editingRule.conditions.map((c) => {
            if (c.tempId !== tid) return c;
            let next = { ...c, [fld]: val };
            if (fld === "operator") {
                next.showValue = !NO_VAL.has(val);
                if (!next.showValue) next.value = "";
            }
            return next;
        });
        this.editingRule = { ...this.editingRule, conditions, _lastEditedLabel: "Last edited just now" };
    }

    handleCondInputChange(e) {
        const tid = e.target.dataset.tempid;
        const val = e.target.value;
        const conditions = this.editingRule.conditions.map((c) => (c.tempId !== tid ? c : { ...c, value: val }));
        this.editingRule = { ...this.editingRule, conditions, _lastEditedLabel: "Last edited just now" };
    }

    // ── Save ──────────────────────────────────────────────────────────
    async handleSaveRule() {
        const err = this.validate();
        if (err) {
            this.toast("Validation", err, "warning");
            return;
        }
        this.isSaving = true;

        const strippedConditions = this.editingRule.conditions.map(
            ({ tempId, operatorOptions, showValue, isPicklist, valueOptions, displayIndex, ...rest }, i) => ({
                ...rest,
                order: i + 1
            })
        );
        const payload = {
            developerName: this.editingRule.developerName,
            label: this.editingRule.label,
            order: this.editingRule.order,
            isActive: this.editingRule.isActive,
            assignToType: this.editingRule.assignToType,
            assignToId: this.editingRule.assignToId,
            assignToName: this.editingRule.assignToName,
            conditionLogic: this.editingRule.conditionLogic,
            stopOnMatch: this.editingRule.stopOnMatch,
            conditions: strippedConditions
        };

        try {
            const jobId = await saveRule({ ruleJson: JSON.stringify(payload) });
            this.editingRule = null;
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
        if (!r.assignToId) return `Select a target ${r.assignToType}.`;
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

    // ── Deploy polling ────────────────────────────────────────────────
    async deployAndPoll(jobId, successMsg, label) {
        this.isDeploying = true;
        this.deployingMsg = label || "Saving…";
        let polls = 0;
        try {
            while (polls < MAX_POLL) {
                await this._sleep(POLL_MS);
                polls++;
                try {
                    const status = await checkDeployStatus({ jobId });
                    if (status === "Succeeded") {
                        await this.loadAll();
                        this.toast("Saved", successMsg, "success");
                        return;
                    }
                    this.deployingMsg = `${label} (${polls * (POLL_MS / 1000)}s)`;
                } catch (pollErr) {
                    this.toast("Deploy Failed", this.errMsg(pollErr), "error");
                    return;
                }
            }
            this.toast("Still deploying…", "Check Setup → Deployment Status.", "warning");
        } finally {
            this.isDeploying = false;
            this.deployingMsg = "";
        }
    }

    _sleep(ms) {
        return new Promise((r) => setTimeout(r, ms));
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