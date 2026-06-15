import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRules from "@salesforce/apex/AssignmentRuleController.getRules";
import getIntakeFields from "@salesforce/apex/AssignmentRuleController.getIntakeFields";
import getQueues from "@salesforce/apex/AssignmentRuleController.getQueues";
import getUsers from "@salesforce/apex/AssignmentRuleController.getUsers";
import saveRule from "@salesforce/apex/AssignmentRuleController.saveRule";
import toggleRule from "@salesforce/apex/AssignmentRuleController.toggleRule";
import reorderRules from "@salesforce/apex/AssignmentRuleController.reorderRules";

let _uid = 0;
const nextId = () => `cid_${++_uid}`;

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
            // pre-computed display
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
            const v = c.value ? ` "${c.value}"` : "";
            return `${c.fieldApiName || "?"} ${c.operator || "?"}${v}`;
        }
        return `${conds.length} conditions [${r.conditionLogic || "AND"}]`;
    }

    // ── Getters ────────────────────────────────────────────────────
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

    // ── Left panel actions ─────────────────────────────────────────
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
            _devNameLocked: false // new rule — keep deriving from label as user types
        };
    }

    handleSelectRule(e) {
        const rule = this.rules.find((r) => r.developerName === e.currentTarget.dataset.devname);
        if (!rule) return;
        this.editingRule = {
            ...rule,
            conditions: rule.conditions.map((c, i) => ({ ...c, tempId: nextId(), displayIndex: i + 1 })),
            targetOptions: this.targetOpts(rule.assignToType),
            _devNameLocked: true // existing rule - never overwrite the saved developerName
        };
    }

    async handleToggleRule(e) {
        e.stopPropagation();
        const devName = e.currentTarget.dataset.devname;
        const rule = this.rules.find((r) => r.developerName === devName);
        if (!rule) return;
        try {
            await toggleRule({ developerName: devName, isActive: !rule.isActive });
            this.toast("Updated", `Rule ${!rule.isActive ? "activated" : "deactivated"}.`, "success");
            setTimeout(() => this.loadAll(), 5000);
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
            await reorderRules({ orderedDeveloperNames: arr.map((r) => r.developerName) });
            setTimeout(() => this.loadAll(), 5000);
        } catch (e2) {
            this.toast("Error", this.errMsg(e2), "error");
        }
    }

    stopProp(e) {
        e.stopPropagation();
    }

    // ── Editor: rule-level ─────────────────────────────────────────
    handleRuleFieldChange(e) {
        const fld = e.currentTarget.dataset.fld;
        const val = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
        let patch = { [fld]: val };

        // Keep auto-deriving developerName from label until the rule is saved once
        if (fld === "label" && !this.editingRule._devNameLocked) {
            patch.developerName = this.safeDevName(val);
        }
        if (fld === "assignToType") {
            patch.targetOptions = this.targetOpts(val);
            patch.assignToId = "";
            patch.assignToName = "";
        }
        if (fld === "assignToId") {
            const opts = this.editingRule.targetOptions || [];
            const opt = opts.find((o) => o.value === val);
            patch.assignToName = opt ? opt.label : "";
        }
        this.editingRule = { ...this.editingRule, ...patch };
    }

    // ── Editor: condition-level ────────────────────────────────────
    handleAddCondition() {
        const idx = this.editingRule.conditions.length;
        const cond = this.buildCond({}, idx);
        this.editingRule = {
            ...this.editingRule,
            conditions: [...this.editingRule.conditions, cond]
        };
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
        // strip LWC-only view props before sending to Apex
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
        // strip rule-level view props too
        delete payload.activeBadgeClass;
        delete payload.activeLabel;
        delete payload.targetOptions;
        delete payload.conditionSummary;
        delete payload.cardClass;
        try {
            await saveRule({ ruleJson: JSON.stringify(payload) });
            this.toast("Queued", "Rule is deploying — changes appear in ~10 seconds.", "success");
            this.editingRule = null;
            setTimeout(() => this.loadAll(), 10000);
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

        // Duplicate developerName check — catches same-name rules before the async deploy
        if (!r._devNameLocked) {
            const taken = this.rules.some((existing) => existing.developerName === r.developerName);
            if (taken)
                return `A rule named "${r.label}" already exists (developer name "${r.developerName}" is taken). Use a different rule name.`;
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
