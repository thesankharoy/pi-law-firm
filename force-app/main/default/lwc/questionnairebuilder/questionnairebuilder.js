import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent }    from 'lightning/platformShowToastEvent';
import { NavigationMixin }   from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import getQuestionnaireData  from '@salesforce/apex/QuestionnaireBuilderController.getQuestionnaireData';
import getAllQuestions        from '@salesforce/apex/QuestionnaireBuilderController.getAllQuestions';
import getMappingFields      from '@salesforce/apex/QuestionnaireBuilderController.getMappingFields';
import saveQuestionnaireData from '@salesforce/apex/QuestionnaireBuilderController.saveQuestionnaireData';

import NAME_FIELD      from '@salesforce/schema/Questionnaire__c.Name';
import ACTIVE_FIELD    from '@salesforce/schema/Questionnaire__c.Active_Questionnaire__c';
import AVAILABLE_FIELD from '@salesforce/schema/Questionnaire__c.Available_Questionnaire__c';

let _tempId = 0;
function tempId() { return 'tmp-' + (++_tempId); }

// ─────────────────────────────────────────────────────────────────────────────
// Maps your Question__c.Question_Type__c picklist values → the Salesforce
// field types that are compatible for mapping.
//
// Salesforce schema types (from DescribeFieldResult.getType()):
//   STRING, TEXTAREA, EMAIL, PHONE, URL
//   INTEGER, DOUBLE, CURRENCY, PERCENT
//   BOOLEAN
//   DATE, DATETIME
//   PICKLIST, MULTIPICKLIST
//   REFERENCE (lookup/master-detail)
//
// Adjust the keys below to match the exact API values your org uses
// in the Question_Type__c picklist.
// ─────────────────────────────────────────────────────────────────────────────
const QUESTION_TYPE_TO_SF_TYPES = {
    // ── Text family ──────────────────────────────────────────────────────────
    'STRING'        : ['STRING', 'TEXTAREA', 'EMAIL', 'PHONE', 'URL'],
    'Text'          : ['STRING', 'TEXTAREA', 'EMAIL', 'PHONE', 'URL'],
    'TEXT'          : ['STRING', 'TEXTAREA', 'EMAIL', 'PHONE', 'URL'],
    'TEXTAREA'      : ['STRING', 'TEXTAREA'],
    'TEXTAREA_LONG' : ['TEXTAREA', 'STRING'],
    'TEXTAREA_RICH' : ['TEXTAREA', 'STRING'],
    'ENCRYPTED'     : ['STRING', 'ENCRYPTEDSTRING'],
    'EMAIL'         : ['EMAIL', 'STRING'],
    'PHONE'         : ['PHONE', 'STRING'],
    'URL'           : ['URL', 'STRING'],

    // ── Number family ────────────────────────────────────────────────────────
    'NUMBER'    : ['INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT'],
    'Number'    : ['INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT'],
    'INTEGER'   : ['INTEGER', 'DOUBLE'],
    'DECIMAL'   : ['DOUBLE', 'CURRENCY', 'PERCENT', 'INTEGER'],
    'Decimal'   : ['DOUBLE', 'CURRENCY', 'PERCENT', 'INTEGER'],
    'CURRENCY'  : ['CURRENCY', 'DOUBLE'],
    'PERCENT'   : ['PERCENT', 'DOUBLE'],

    // ── Boolean ──────────────────────────────────────────────────────────────
    'BOOLEAN'   : ['BOOLEAN'],
    'Boolean'   : ['BOOLEAN'],
    'Checkbox'  : ['BOOLEAN'],
    'CHECKBOX'  : ['BOOLEAN'],

    // ── Date / time ──────────────────────────────────────────────────────────
    'DATE'      : ['DATE'],
    'Date'      : ['DATE'],
    'DATETIME'  : ['DATETIME', 'DATE'],
    'DateTime'  : ['DATETIME', 'DATE'],
    'TIME'      : ['TIME'],

    // ── Picklist / select ────────────────────────────────────────────────────
    'SELECT'       : ['PICKLIST', 'STRING'],
    'Picklist'     : ['PICKLIST', 'STRING'],
    'PICKLIST'     : ['PICKLIST', 'STRING'],
    'MULTISELECT'  : ['MULTIPICKLIST', 'STRING'],
    'Multiselect'  : ['MULTIPICKLIST', 'STRING'],
    'MULTIPICKLIST': ['MULTIPICKLIST', 'STRING'],

    // ── Lookup ───────────────────────────────────────────────────────────────
    'LOOKUP'    : ['REFERENCE'],
    'Lookup'    : ['REFERENCE'],
    'REFERENCE' : ['REFERENCE'],

    // ── Address ──────────────────────────────────────────────────────────────
    'ADDRESS'   : ['ADDRESS'],
};

export default class QuestionnaireBuilder extends NavigationMixin(LightningElement) {

    @api recordId;

    @track questionnaireName = '';
    @track isActive   = false;
    @track isAvailable = false;

    @track nodes = [];
    @track selectedNodeTempId = null;

    @track nodeQuestions = {};
    @track nodeNavRules  = {};

    @track isEditingNode    = false;
    @track editingNodeTempId = null;
    @track editingNodeName   = '';

    // questionOptions now carries { label, value, questionType }
    @track questionOptions  = [];
    // mappingOptions now carries { label, value, fieldType }
    @track mappingOptions   = [];

    @track isSaving = false;

    @wire(getRecord, { recordId: '$recordId', fields: [NAME_FIELD, ACTIVE_FIELD, AVAILABLE_FIELD] })
    wiredRecord({ data, error }) {
        if (data) {
            this.questionnaireName = getFieldValue(data, NAME_FIELD)      || '';
            this.isActive          = getFieldValue(data, ACTIVE_FIELD)    || false;
            this.isAvailable       = getFieldValue(data, AVAILABLE_FIELD) || false;
        }
    }

    connectedCallback() {
        this.loadDropdowns();
        if (this.recordId) {
            this.loadExistingData();
        }
    }

    loadDropdowns() {
        Promise.all([
            getAllQuestions(),
            getMappingFields()
        ]).then(([questions, mappings]) => {
            // Store questionType so we can filter mappings per row
            this.questionOptions = questions.map(q => ({
                label:        q.Question_Text__c || q.Name,
                value:        q.Id,
                questionType: q.Question_Type__c || ''
            }));
            // Store fieldType returned by the updated Apex method
            this.mappingOptions = mappings.map(f => ({
                label:     f.label,
                value:     f.value,
                fieldType: (f.fieldType || '').toUpperCase()
            }));
        }).catch(err => {
            this.showToast('Error', this.errMsg(err), 'error');
        });
    }

    loadExistingData() {
        getQuestionnaireData({ questionnaireId: this.recordId })
            .then(data => {
                const nodeMap = {};
                this.nodes = (data.nodes || []).map((n, idx) => {
                    const tid = tempId();
                    nodeMap[n.Id] = tid;
                    return {
                        tempId:     tid,
                        sfId:       n.Id,
                        Name:       n.Name,
                        Order__c:   n.Order__c || (idx + 1),
                        isSelected: idx === 0,
                        itemClass:  idx === 0 ? 'node-item node-item_active' : 'node-item'
                    };
                });

                if (this.nodes.length > 0) {
                    this.selectedNodeTempId = this.nodes[0].tempId;
                }

                const nq = {};
                this.nodes.forEach(n => { nq[n.tempId] = []; });
                (data.nodeQuestions || []).forEach(nqRec => {
                    const tid = nodeMap[nqRec.Question_Node__c];
                    if (tid) {
                        nq[tid] = nq[tid] || [];
                        nq[tid].push({
                            tempId:      tempId(),
                            sfId:        nqRec.Id,
                            questionId:  nqRec.Question__c,
                            description: nqRec.Description__c || '',
                            mapping:     nqRec.Mapping__c     || '',
                            required:    nqRec.Required__c    || false
                        });
                    }
                });
                this.nodeQuestions = nq;

                const nn = {};
                this.nodes.forEach(n => { nn[n.tempId] = []; });
                (data.navRules || []).forEach(nav => {
                    const tid = nodeMap[nav.Source_Node__c];
                    if (tid) {
                        nn[tid] = nn[tid] || [];
                        let rules = [];
                        try { rules = JSON.parse(nav.Rules_JSON__c || '[]'); } catch(e) { rules = []; }
                        const targetTid = nodeMap[nav.Target_Node__c] || nav.Target_Node__c || '';
                        nn[tid].push({
                            tempId:       tempId(),
                            sfId:         nav.Id,
                            targetNodeId: targetTid,
                            rules: rules.map(r => ({ ...r, tempId: tempId() }))
                        });
                    }
                });
                this.nodeNavRules = nn;
            })
            .catch(err => {
                this.showToast('Error', this.errMsg(err), 'error');
            });
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get selectedNode() {
        return this.nodes.find(n => n.tempId === this.selectedNodeTempId) || null;
    }

    get selectedNodeQuestions() {
        if (!this.selectedNodeTempId) return [];
        const rows = this.nodeQuestions[this.selectedNodeTempId] || [];

        // Collect ALL mappings already in use across the entire questionnaire
        const usedMappings = new Set();
        Object.values(this.nodeQuestions).forEach(nodeRows => {
            nodeRows.forEach(row => {
                if (row.mapping) usedMappings.add(row.mapping);
            });
        });

        return rows.map(row => {
            // 1. Find what Question_Type__c this row's chosen question has
            const questionOption = this.questionOptions.find(o => o.value === row.questionId);
            const questionType   = questionOption ? questionOption.questionType : '';

            // 2. Look up which SF field types are compatible with that question type
            const compatibleSfTypes = QUESTION_TYPE_TO_SF_TYPES[questionType] || null;
            // null means "no filter" (unknown question type → show everything)

            // 3. Filter mapping options:
            //    a) type must match (or no filter if unknown type)
            //    b) not already used elsewhere UNLESS it's the value currently on THIS row
            const filteredMappingOptions = this.mappingOptions.filter(opt => {
                const typeOk    = !compatibleSfTypes || compatibleSfTypes.includes(opt.fieldType);
                const notUsed   = !usedMappings.has(opt.value) || opt.value === row.mapping;
                return typeOk && notUsed;
            });

            return {
                ...row,
                filteredMappingOptions
            };
        });
    }

    get selectedNodeNavRules() {
        if (!this.selectedNodeTempId) return [];
        return this.nodeNavRules[this.selectedNodeTempId] || [];
    }

    get nodeOptions() {
        return this.nodes
            .filter(n => n.tempId !== this.selectedNodeTempId)
            .map(n => ({ label: n.Name, value: n.tempId }));
    }

    get currentQuestionnaireId() {
        return this.recordId || 'current';
    }

    get currentQuestionnaireOptions() {
        return [{
            label: this.questionnaireName || 'This Questionnaire',
            value: this.currentQuestionnaireId
        }];
    }

    get operatorOptions() {
        return [
            { label: 'equals',       value: 'equals'      },
            { label: 'not equals',   value: 'not_equals'  },
            { label: 'contains',     value: 'contains'    },
            { label: 'is blank',     value: 'is_blank'    },
            { label: 'is not blank', value: 'is_not_blank'}
        ];
    }

    // ── Questionnaire header ──────────────────────────────────────────────────

    handleNameChange(e)      { this.questionnaireName = e.detail.value; }
    handleActiveChange(e)    { this.isActive    = e.detail.checked; }
    handleAvailableChange(e) { this.isAvailable = e.detail.checked; }

    // ── Node sidebar ──────────────────────────────────────────────────────────

    handleNodeSelect(event) {
        const tid = event.currentTarget.dataset.id;
        if (tid !== this.editingNodeTempId) {
            this.isEditingNode     = false;
            this.editingNodeTempId = null;
        }
        this.selectNode(tid);
    }

    selectNode(tid) {
        this.selectedNodeTempId = tid;
        this.nodes = this.nodes.map(n => ({
            ...n,
            isSelected: n.tempId === tid,
            itemClass:  n.tempId === tid ? 'node-item node-item_active' : 'node-item'
        }));
    }

    addNode() {
        const tid   = tempId();
        const order = this.nodes.length + 1;
        const newNode = {
            tempId:     tid,
            sfId:       null,
            Name:       'Node ' + order,
            Order__c:   order,
            isSelected: false,
            itemClass:  'node-item'
        };
        this.nodes = [...this.nodes, newNode];
        this.nodeQuestions = { ...this.nodeQuestions, [tid]: [] };
        this.nodeNavRules  = { ...this.nodeNavRules,  [tid]: [] };
        this.selectNode(tid);
        this.startNodeEdit(tid, newNode.Name);
    }

    handleNodeEdit(event) {
        event.stopPropagation();
        const tid  = event.currentTarget.dataset.id;
        const node = this.nodes.find(n => n.tempId === tid);
        if (node) this.startNodeEdit(tid, node.Name);
    }

    startNodeEdit(tid, currentName) {
        this.isEditingNode     = true;
        this.editingNodeTempId = tid;
        this.editingNodeName   = currentName;
        this.selectNode(tid);
    }

    handleEditingNodeName(e) { this.editingNodeName = e.detail.value; }

    handleNodeNameKeyup(e) {
        if (e.key === 'Enter') this.confirmNodeEdit();
    }

    confirmNodeEdit() {
        const newName = this.editingNodeName.trim();
        if (!newName) return;
        this.nodes = this.nodes.map(n =>
            n.tempId === this.editingNodeTempId ? { ...n, Name: newName } : n
        );
        this.isEditingNode     = false;
        this.editingNodeTempId = null;
    }

    handleNodeDelete(event) {
        event.stopPropagation();
        const tid = event.currentTarget.dataset.id;
        this.nodes = this.nodes.filter(n => n.tempId !== tid);
        const nq = { ...this.nodeQuestions }; delete nq[tid];
        const nn = { ...this.nodeNavRules };  delete nn[tid];
        this.nodeQuestions = nq;
        this.nodeNavRules  = nn;
        if (this.selectedNodeTempId === tid) {
            this.selectedNodeTempId = this.nodes.length > 0 ? this.nodes[0].tempId : null;
        }
        if (this.editingNodeTempId === tid) {
            this.isEditingNode     = false;
            this.editingNodeTempId = null;
        }
    }

    // ── Question rows ─────────────────────────────────────────────────────────

    addQuestionRow() {
        const tid = this.selectedNodeTempId;
        if (!tid) return;
        const newRow = { tempId: tempId(), sfId: null, questionId: '', description: '', mapping: '', required: false };
        this.nodeQuestions = {
            ...this.nodeQuestions,
            [tid]: [...(this.nodeQuestions[tid] || []), newRow]
        };
    }

    handleQuestionSelect(e) {
        const newQuestionId = e.detail.value;
        const rowTempId     = e.target.dataset.id;

        // Duplicate check across ALL nodes
        const allRows = [];
        Object.entries(this.nodeQuestions).forEach(([, rows]) => {
            rows.forEach(row => {
                if (row.tempId !== rowTempId) allRows.push(row);
            });
        });

        const isDuplicateQuestion = allRows.some(r => r.questionId === newQuestionId);
        if (isDuplicateQuestion) {
            this.showToast('Duplicate Question', 'This question is already used in this questionnaire.', 'error');
            return;
        }

        // Clear the mapping when the question type changes (avoid type mismatch)
        const tid        = this.selectedNodeTempId;
        const currentRow = (this.nodeQuestions[tid] || []).find(r => r.tempId === rowTempId);
        const oldType    = currentRow
            ? (this.questionOptions.find(o => o.value === currentRow.questionId) || {}).questionType
            : null;
        const newType    = (this.questionOptions.find(o => o.value === newQuestionId) || {}).questionType;

        const shouldClearMapping = oldType && newType && oldType !== newType;

        this.nodeQuestions = {
            ...this.nodeQuestions,
            [tid]: (this.nodeQuestions[tid] || []).map(q =>
                q.tempId === rowTempId
                    ? { ...q, questionId: newQuestionId, mapping: shouldClearMapping ? '' : q.mapping }
                    : q
            )
        };
    }

    handleQuestionDesc(e)    { this.updateQuestionRow(e.target.dataset.id, 'description', e.detail.value); }
    handleQuestionMapping(e) { this.updateQuestionRow(e.target.dataset.id, 'mapping',     e.detail.value); }

    handleRemoveQuestion(e) {
        const tid   = this.selectedNodeTempId;
        const rowId = e.currentTarget.dataset.id;
        this.nodeQuestions = {
            ...this.nodeQuestions,
            [tid]: (this.nodeQuestions[tid] || []).filter(q => q.tempId !== rowId)
        };
    }

    updateQuestionRow(rowTempId, field, value) {
        const tid = this.selectedNodeTempId;
        this.nodeQuestions = {
            ...this.nodeQuestions,
            [tid]: (this.nodeQuestions[tid] || []).map(q =>
                q.tempId === rowTempId ? { ...q, [field]: value } : q
            )
        };
    }

    // ── Navigation rows ───────────────────────────────────────────────────────

    addNavRow() {
        const tid = this.selectedNodeTempId;
        if (!tid) return;
        const newRow = { tempId: tempId(), sfId: null, targetNodeId: '', rules: [] };
        this.nodeNavRules = {
            ...this.nodeNavRules,
            [tid]: [...(this.nodeNavRules[tid] || []), newRow]
        };
    }

    handleNavNode(e) { this.updateNavRow(e.target.dataset.id, 'targetNodeId', e.detail.value); }

    handleRemoveNavRow(e) {
        const tid   = this.selectedNodeTempId;
        const navId = e.currentTarget.dataset.id;
        this.nodeNavRules = {
            ...this.nodeNavRules,
            [tid]: (this.nodeNavRules[tid] || []).filter(n => n.tempId !== navId)
        };
    }

    updateNavRow(navTempId, field, value) {
        const tid = this.selectedNodeTempId;
        this.nodeNavRules = {
            ...this.nodeNavRules,
            [tid]: (this.nodeNavRules[tid] || []).map(n =>
                n.tempId === navTempId ? { ...n, [field]: value } : n
            )
        };
    }

    // ── Rules ─────────────────────────────────────────────────────────────────

    addRule(e) {
        const navId   = e.currentTarget.dataset.id;
        const tid     = this.selectedNodeTempId;
        const newRule = { tempId: tempId(), questionId: '', operator: 'equals', value: '' };
        this.nodeNavRules = {
            ...this.nodeNavRules,
            [tid]: (this.nodeNavRules[tid] || []).map(n =>
                n.tempId === navId ? { ...n, rules: [...n.rules, newRule] } : n
            )
        };
    }

    handleRuleQuestion(e) { this.updateRule(e, 'questionId', e.detail.value); }
    handleRuleOperator(e) { this.updateRule(e, 'operator',   e.detail.value); }
    handleRuleValue(e)    { this.updateRule(e, 'value',       e.detail.value); }

    handleRemoveRule(e) {
        const navId  = e.currentTarget.dataset.navId;
        const ruleId = e.currentTarget.dataset.ruleId;
        const tid    = this.selectedNodeTempId;
        this.nodeNavRules = {
            ...this.nodeNavRules,
            [tid]: (this.nodeNavRules[tid] || []).map(n =>
                n.tempId === navId
                    ? { ...n, rules: n.rules.filter(r => r.tempId !== ruleId) }
                    : n
            )
        };
    }

    updateRule(e, field, value) {
        const navId  = e.target.dataset.navId;
        const ruleId = e.target.dataset.ruleId;
        const tid    = this.selectedNodeTempId;
        this.nodeNavRules = {
            ...this.nodeNavRules,
            [tid]: (this.nodeNavRules[tid] || []).map(n =>
                n.tempId === navId
                    ? { ...n, rules: n.rules.map(r => r.tempId === ruleId ? { ...r, [field]: value } : r) }
                    : n
            )
        };
    }

    // ── Save ──────────────────────────────────────────────────────────────────

    handleSave() {
        if (!this.questionnaireName || !this.questionnaireName.trim()) {
            this.showToast('Validation Error', 'Please enter a questionnaire name.', 'error');
            return;
        }

        this.isSaving = true;

        const nodeTempIdToIndex = {};
        this.nodes.forEach((n, idx) => { nodeTempIdToIndex[n.tempId] = idx; });

        const nodesPayload = this.nodes.map((n, idx) => ({
            sfId:     n.sfId || '',
            Name:     n.Name,
            Order__c: idx + 1,
            questions: (this.nodeQuestions[n.tempId] || []).map(q => ({
                sfId:        q.sfId || '',
                questionId:  q.questionId,
                description: q.description,
                mapping:     q.mapping,
                required:    q.required || false
            })),
            navRules: (this.nodeNavRules[n.tempId] || []).map(nav => {
                const hasIndex = nodeTempIdToIndex.hasOwnProperty(nav.targetNodeId);
                return {
                    sfId:            nav.sfId || '',
                    targetNodeIndex: hasIndex ? nodeTempIdToIndex[nav.targetNodeId] : null,
                    targetNodeId:    hasIndex ? '' : nav.targetNodeId,
                    rulesJson: JSON.stringify(nav.rules.map(r => ({
                        questionId: r.questionId,
                        operator:   r.operator,
                        value:      r.value
                    })))
                };
            })
        }));

        saveQuestionnaireData({
            questionnaireId: this.recordId || '',
            name:            this.questionnaireName,
            isActive:        this.isActive,
            isAvailable:     this.isAvailable,
            nodesJson:       JSON.stringify(nodesPayload)
        })
        .then(savedId => {
            this.isSaving = false;
            this.showToast('Success', 'Questionnaire saved successfully!', 'success');
            if (this.recordId) {
                this.loadExistingData();
            } else {
                this.dispatchEvent(new CustomEvent('saved', { detail: { questionId: savedId } }));
            }
        })
        .catch(err => {
            this.isSaving = false;
            this.showToast('Error', this.errMsg(err), 'error');
        });
    }

    handleCancel() {
        if (this.recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.recordId, actionName: 'view' }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__objectPage',
                attributes: { objectApiName: 'Questionnaire__c', actionName: 'list' }
            });
        }
    }

    // ── Utilities ─────────────────────────────────────────────────────────────

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errMsg(err) {
        return err?.body?.message || err?.message || 'An unexpected error occurred.';
    }
}