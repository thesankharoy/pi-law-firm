import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent }               from 'lightning/platformShowToastEvent';
import getSavedQuestionnaire from '@salesforce/apex/IntakeQuestionnaireController.getSavedQuestionnaire';
import getAvailableQuestionnaires from '@salesforce/apex/IntakeQuestionnaireController.getAvailableQuestionnaires';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getQuestionNodes           from '@salesforce/apex/IntakeQuestionnaireController.getQuestionNodes';
import getQuestions               from '@salesforce/apex/IntakeQuestionnaireController.getQuestions';
import getNavigationRules         from '@salesforce/apex/IntakeQuestionnaireController.getNavigationRules';
import getExistingResponses       from '@salesforce/apex/IntakeQuestionnaireController.getExistingResponses';
import saveResponses              from '@salesforce/apex/IntakeQuestionnaireController.saveResponses';
import getAutoQuestionnaire from '@salesforce/apex/IntakeQuestionnaireController.getAutoQuestionnaire';

export default class IntakeQuestionnaire extends LightningElement {

    // ─── Public props ────────────────────────────────────────────────────────
    @api recordId;          // Intake record Id
    @api caseType = '';     // optional filter

    // ─── Tracked state ───────────────────────────────────────────────────────
    @track questionnaires         = [];
    @track selectedQuestionnaire  = null;
    @track selectedQuestionnaireId = '';
    @track autoLockedQuestionnaire = null;
    @track nodes            = [];   // Question_Node__c list (ordered)
    @track questions        = [];   // Question__c list (all nodes)
    @track navigationRules  = [];   // Questionnaire_Navigation__c list

    @track responses        = {};   // { [questionId]: responseText }
    @track savedResponses   = [];   // summary output after final save

    @track currentNodeIndex = 0;    // which node we're on
    @track nodeHistory      = [];   // stack for Back navigation (indexes)

    @track isLoading  = false;
    @track isSaving   = false;
    @track showSummary = false;

    // Boolean yes/no options used for BOOLEAN question type
    get booleanOptions() {
        return [
            { label: 'Yes', value: 'true'  },
            { label: 'No',  value: 'false' }
        ];
    }

    connectedCallback() {
    this.loadQuestionnaires().then(() => {
        // First: check if a questionnaire was previously saved on this intake
        getSavedQuestionnaire({ intakeId: this.recordId })
            .then(saved => {
                if (saved) {
                    this.autoLockedQuestionnaire = saved;
                    this.loadQuestionnaire(saved);
                } else {
                    // No saved questionnaire — try auto-match by Incident_Type__c
                    return getAutoQuestionnaire({ intakeId: this.recordId })
                        .then(auto => {
                            if (auto) {
                                this.autoLockedQuestionnaire = auto;
                                this.loadQuestionnaire(auto);
                            }
                        });
                }
            })
            .catch(() => {});
    });
}

    get isAutoLocked() {
    return !!this.autoLockedQuestionnaire;
}

get autoLockedName() {
    return this.autoLockedQuestionnaire ? this.autoLockedQuestionnaire.Name : '';
}

    loadQuestionnaires() {
        return getAvailableQuestionnaires({ caseType: this.caseType })
            .then(data => { this.questionnaires = data; })
            .catch(err => { this.showToast('Error', this.errorMsg(err), 'error'); });
    }

//     checkSavedQuestionnaire() {
//     getSavedQuestionnaire({ intakeId: this.recordId })
//         .then(result => {
//             if (result) {
//                 this.loadQuestionnaire(result);
//             }
//         })
//         .catch(() => {});
// }

    get questionnaireOptions() {
        return this.questionnaires.map(q => ({ label: q.Name, value: q.Id }));
    }

    get isOpenSelectedDisabled() { return !this.selectedQuestionnaireId; }

    handleQuestionnaireSelect(event) {
        this.selectedQuestionnaireId = event.detail.value;
    }

    openSelectedQuestionnaire() {
        const q = this.questionnaires.find(item => item.Id === this.selectedQuestionnaireId);
        if (q) this.loadQuestionnaire(q);
    }

    loadQuestionnaire(questionnaire) {
        this.selectedQuestionnaire  = questionnaire;
        this.isLoading              = true;
        this.currentNodeIndex       = 0;
        this.nodeHistory            = [];
        this.showSummary            = false;

        Promise.all([
            getQuestionNodes   ({ questionnaireId: questionnaire.Id }),
            getQuestions       ({ questionnaireId: questionnaire.Id }),
            getNavigationRules ({ questionnaireId: questionnaire.Id }),
            getExistingResponses({ intakeId: this.recordId, questionnaireId: questionnaire.Id })
        ])
        .then(([nodes, questions, navRules, existingResponses]) => {
            // Build response map from existing data
            const responseMap = {};
            existingResponses.forEach(r => {
                responseMap[r.Question__c] = r.Response_Text__c;
            });
            this.responses       = responseMap;
            this.nodes           = nodes;
            this.questions       = questions;
            this.navigationRules = navRules;
            this.isLoading       = false;

            if (existingResponses.length > 0) {
    this.buildSavedResponsesOutput();
    this.showSummary = true;
}
        })
        .catch(err => {
            this.isLoading = false;
            this.showToast('Error', this.errorMsg(err), 'error');
        });
    }

    resetQuestionnaire() {
        this.selectedQuestionnaire   = null;
        this.selectedQuestionnaireId = '';
        this.nodes                   = [];
        this.questions               = [];
        this.navigationRules         = [];
        this.responses               = {};
        this.savedResponses          = [];
        this.currentNodeIndex        = 0;
        this.nodeHistory             = [];
        this.showSummary             = false;
    }

    get currentNode() {
        return this.nodes[this.currentNodeIndex] || null;
    }

    get isFirstNode()      { return this.nodeHistory.length === 0; }
    get isLastNode()       { return this.currentNodeIndex === this.nodes.length - 1; }
    get hasMultipleNodes() { return this.nodes.length > 1; }
    get currentStepNumber() { return this.currentNodeIndex + 1; }
    get totalSteps()        { return this.nodes.length; }

    /** Pills shown at top to indicate progress */
    get nodeProgressList() {
    return this.nodes.map((n, idx) => {
        const isActive = idx === this.currentNodeIndex;
        const isDone   = idx < this.currentNodeIndex;
        return {
            id:             n.Id,
            name:           n.Name,
            shortName:      n.Name.length > 12 ? n.Name.substring(0, 12) + '…' : n.Name,
            stepNumber:     idx + 1,
            markerContent:  isDone ? '✓' : String(idx + 1),
            trackItemClass: 'step-item' + (isActive ? ' step-item_active' : isDone ? ' step-item_done' : ''),
            markerClass:    'step-marker'
        };
    });
}

    // buildPillClass(idx) {
    //     const base = 'node-pill slds-badge slds-m-right_x-small slds-m-bottom_x-small ';
    //     if (idx === this.currentNodeIndex) return base + 'node-pill_active';
    //     if (idx < this.currentNodeIndex)   return base + 'node-pill_done';
    //     return base + 'node-pill_pending';
    // }

    get currentNodeQuestions() {
    if (!this.currentNode) return [];
    return this.questions
        .filter(q => q.Question_Node__c === this.currentNode.Id)
        .map(q   => this.enrichQuestion(q));
}

   enrichQuestion(q) {
    let response = this.responses[q.Id] || '';
    const qType = q.Question_Type__c || '';

    // Normalize time values back to HH:mm for lightning-input type="time"
    const isTime = ['TIME'].includes(qType);
    if (isTime && response) {
        response = this.normalizeTimeValue(response);
    }

    const currentSelections = response ? response.split(';') : [];

    // ── Text family ───────────────────────────────────────────────
    const isText     = ['Text', 'STRING', 'TEXT', 'URL', 'ENCRYPTED'].includes(qType);
    const isEmail    = ['Email', 'EMAIL'].includes(qType);
    const isPhone    = ['Phone', 'PHONE'].includes(qType);
    const isTextarea = ['Textarea', 'TEXTAREA', 'TEXTAREA_LONG', 'TEXTAREA_RICH'].includes(qType);

    // ── Number family ─────────────────────────────────────────────
    const isNumber = ['Number', 'NUMBER', 'INTEGER', 'DECIMAL',
                       'CURRENCY', 'PERCENT'].includes(qType);

    // ── Boolean / Checkbox ────────────────────────────────────────
    const isCheckbox = ['Checkbox'].includes(qType);
    const isBoolean  = ['Boolean', 'BOOLEAN'].includes(qType);

    // ── Date / Time ───────────────────────────────────────────────
    const isDate     = ['Date', 'DATE'].includes(qType);
    const isDateTime = ['DATETIME'].includes(qType);

    // ── Picklist ──────────────────────────────────────────────────
    const isPicklist    = ['Picklist', 'SELECT', 'PICKLIST'].includes(qType);
    const isMultiSelect = ['Multiselect', 'MULTISELECT', 'MULTIPICKLIST'].includes(qType);

    // ── Address ───────────────────────────────────────────────────
    const isAddress = ['ADDRESS'].includes(qType);

    const isKnownType = isText || isEmail || isPhone || isTextarea ||
                        isNumber || isCheckbox || isBoolean ||
                        isDate || isDateTime || isTime ||
                        isPicklist || isMultiSelect || isAddress;

    return {
        ...q,
        response,
        responseBoolean: response === 'true',
        isVisible:       this.checkVisibility(q),
        rowClass:        'question-row' + (q.Is_Required__c ? ' question-row_required' : ''),
        isText, isEmail, isPhone, isTextarea,
        isNumber, isCheckbox, isBoolean,
        isDate, isDateTime, isTime,
        isPicklist, isMultiSelect, isAddress,
        isOther: !isKnownType,
        picklistOptions: this.buildPicklistOptions(
            q.Picklist_Options__c, currentSelections, qType
        )
    };
}

    checkVisibility(question) {
        if (!question.Is_Conditional__c || !question.Condition_Question__c) return true;
        const conditionAnswer = this.responses[question.Condition_Question__c];
        return conditionAnswer === question.Condition_Value__c;
    }

    buildPicklistOptions(optionsString, currentSelections, type) {
        if (!optionsString) return [];
        return optionsString.split(',').map((opt, idx) => {
            const trimmed = opt.trim();
            return {
                label:   trimmed,
                value:   trimmed,
                inputId: `ms-opt-${idx}-${trimmed.replace(/\s/g, '_')}`,
                checked: currentSelections.includes(trimmed)
            };
        });
    }

    handleResponseChange(event) {
        const questionId = event.target.dataset.id;
        const value      = event.detail.value;
        this.responses   = { ...this.responses, [questionId]: value };
    }

    handleCheckboxChange(event) {
        const questionId = event.target.dataset.id;
        const value      = String(event.detail.checked);
        this.responses   = { ...this.responses, [questionId]: value };
    }

    handleMultiSelectChange(event) {
        const questionId = event.target.dataset.id;
        const optValue   = event.target.dataset.value;
        const checked    = event.target.checked;

        const existing   = this.responses[questionId]
            ? this.responses[questionId].split(';').filter(v => v)
            : [];

        let updated;
        if (checked) {
            updated = [...new Set([...existing, optValue])];
        } else {
            updated = existing.filter(v => v !== optValue);
        }

        this.responses = { ...this.responses, [questionId]: updated.join(';') };
    }

    goToNextNode() {
    console.log('Current Node:', this.currentNode.Name);

    const nextIdx = this.resolveNextNode();

    console.log('Next Index:', nextIdx);
    console.log('Nodes:', JSON.stringify(this.nodes));

    if (nextIdx !== null) {
        this.nodeHistory.push(this.currentNodeIndex);
        this.currentNodeIndex = nextIdx;
        this.showSummary = false;
    }
}

    /** Back: pop from history stack */
    goToPreviousNode() {
        if (this.nodeHistory.length > 0) {
            this.currentNodeIndex = this.nodeHistory.pop();
            this.showSummary      = false;
        }
    }

    resolveNextNode() {
        if (!this.currentNode) return null;

        const sourceNodeId = this.currentNode.Id;

        // Get rules for this node, already ordered by Order__c from Apex
        const nodeRules = this.navigationRules.filter(
            r => r.Source_Node__c === sourceNodeId
        );

        for (const rule of nodeRules) {
    console.log('Rule Found:', JSON.stringify(rule));

    if (this.evaluateNavRule(rule)) {
        console.log('Rule Matched:', rule.Target_Node__c);

        const targetIdx =
            this.nodes.findIndex(
                n => n.Id === rule.Target_Node__c
            );

        console.log('Target Index:', targetIdx);

        if (targetIdx !== -1) {
            return targetIdx;
        }
    }
}
        // Default: go to the very next node in order
        const nextIdx = this.currentNodeIndex + 1;
        return nextIdx < this.nodes.length ? nextIdx : null;
        console.log(
    'Navigation Rules',
    JSON.stringify(this.navigationRules)
);
    }

    evaluateNavRule(rule) {
    let conditions = [];
    try {
        conditions = JSON.parse(rule.Rules_JSON__c || '[]');
    } catch (e) {
        conditions = [];
    }

    // No conditions on this rule = unconditional/default navigation
    if (conditions.length === 0) return true;

    return conditions.every(cond => {
        const answer   = (this.responses[cond.questionId] || '').toLowerCase();
        const expected = (cond.value || '').toLowerCase();
        const op       = (cond.operator || 'equals').toLowerCase();

        switch (op) {
            case 'equals':       return answer === expected;
            case 'not_equals':   return answer !== expected;
            case 'contains':     return answer.includes(expected);
            case 'is_blank':     return answer === '';
            case 'is_not_blank': return answer !== '';
            default:             return answer === expected;
        }
    });
}

   validateCurrentNode() {
    const missing = [];
    this.currentNodeQuestions.forEach(q => {
        if (q.Is_Required__c && q.isVisible && !this.responses[q.Id]) {
            missing.push(q.Question_Text__c || q.Id);
        }
    });
    if (missing.length > 0) {
        this.showToast(
            'Validation Error',
            `Please fill in: ${missing.join(', ')}`,
            'error'
        );
        return false;
    }
    return true;
}

    validateAllNodes() {
        let isValid = true;
        this.questions.forEach(q => {
            const enriched = this.enrichQuestion(q);
            if (enriched.Is_Required__c && enriched.isVisible && !this.responses[q.Id]) {
                isValid = false;
            }
        });
        if (!isValid) {
            this.showToast('Validation Error', 'Please fill in all required fields.', 'error');
        }
        return isValid;
    }

    handleSave() {
        this.isSaving = true;

        const responsesPayload = Object.entries(this.responses)
        .filter(([, val]) => val !== '' && val !== null && val !== undefined)
        .map(([questionId, responseText]) => {
            const question = this.questions.find(q => q.Id === questionId);
            return {
                questionId,
                responseText,
                mappingField: question ? question.Mapping__c : null
            };
        });

        saveResponses({
        intakeId        : this.recordId,
        questionnaireId : this.selectedQuestionnaire.Id,
        responsesJson   : JSON.stringify(responsesPayload)
    })
        .then(() => {
            this.isSaving = false;
            this.buildSavedResponsesOutput();
            this.showToast('Success', 'Responses saved successfully!', 'success');
            this.showSummary = true;
            getRecordNotifyChange([{ recordId: this.recordId }]);
        })
        .catch(err => {
            this.isSaving = false;
            this.showToast('Error', this.errorMsg(err), 'error');
        });
    }

   buildSavedResponsesOutput() {
    const output = [];
    this.nodes.forEach(node => {
        const nodeQuestions = this.questions.filter(q => q.Question_Node__c === node.Id);
        const responses = [];
        nodeQuestions.forEach(q => {
            const enriched = this.enrichQuestion(q);
            if (enriched.isVisible && this.responses[q.Id]) {
                let displayValue = this.responses[q.Id];
                if (enriched.isTime) {
                    displayValue = this.formatTimeForDisplay(displayValue);
                }
                responses.push({
                    questionId  : q.Id,
                    questionText: q.Question_Text__c,
                    responseText: displayValue
                });
            }
        });
        if (responses.length > 0) {
            output.push({
                nodeId   : node.Id,
                nodeName : node.Name,
                responses: responses
            });
        }
    });
    this.savedResponses = output;
}

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMsg(err) {
        return err?.body?.message || err?.message || 'An unexpected error occurred.';
    }

    scrollToTop() {
        const card = this.template.querySelector('lightning-card');
        if (card) card.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    // Normalize a stored time string ("00:15", "00:15:00", "00:15:00.000Z")
// back to "HH:mm" for lightning-input type="time"
normalizeTimeValue(raw) {
    if (!raw) return '';
    // Strip trailing Z if present
    const clean = raw.replace(/Z$/i, '').trim();
    // Already "HH:mm" — return as-is
    if (/^\d{2}:\d{2}$/.test(clean)) return clean;
    // "HH:mm:ss" or "HH:mm:ss.mmm" — take first two parts
    const parts = clean.split(':');
    if (parts.length >= 2) return parts[0].padStart(2,'0') + ':' + parts[1].padStart(2,'0');
    return clean;
}

// Format for human-readable summary ("00:15" → "12:15 AM")
formatTimeForDisplay(raw) {
    if (!raw) return '';
    const clean = raw.replace(/Z$/i, '');
    const parts = clean.split(':');
    let h = parseInt(parts[0], 10);
    const m = parts[1] ? parts[1].padStart(2,'0') : '00';
    const ampm = h >= 12 ? 'PM' : 'AM';
    h = h % 12 || 12;
    return `${h}:${m} ${ampm}`;
}
}