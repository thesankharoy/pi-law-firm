import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableQuestionnaires from '@salesforce/apex/IntakeQuestionnaireController.getAvailableQuestionnaires';
import getQuestions from '@salesforce/apex/IntakeQuestionnaireController.getQuestions';
import getExistingResponses from '@salesforce/apex/IntakeQuestionnaireController.getExistingResponses';
import saveResponses from '@salesforce/apex/IntakeQuestionnaireController.saveResponses';
import getSavedQuestionnaireId from '@salesforce/apex/IntakeQuestionnaireController.getSavedQuestionnaireId';

export default class IntakeQuestionnaire extends LightningElement {
    @api recordId; 
    @api caseType = ''; 

    @track questionnaires = [];
    @track selectedQuestionnaire = null;
    @track selectedQuestionnaireId = '';
    @track questions = [];
    @track sections = [];
    @track responses = {}; 
    @track savedResponses = [];
    @track isLoading = false;
    @track isSaving = false;

    connectedCallback() {
    this.loadQuestionnaires().then(() => {
        this.checkSavedQuestionnaire();
    });
}

   loadQuestionnaires() {
    return getAvailableQuestionnaires({ caseType: this.caseType })
        .then(data => {
            this.questionnaires = data;
        })
        .catch(error => {
            this.showToast('Error', error.body?.message || 'Failed to load questionnaires', 'error');
        });
}

checkSavedQuestionnaire() {
    getSavedQuestionnaireId({ intakeId: this.recordId })
        .then(result => {
            if (result && result.Questionnaire__c) {
                const savedQ = this.questionnaires.find(q => q.Id === result.Questionnaire__c);
                if (savedQ) {
                    this.loadQuestionnaire(savedQ);
                }
            }
        })
        .catch(() => {});
}

    get questionnaireOptions() {
        return this.questionnaires.map(q => ({
            label: q.Name,
            value: q.Id
        }));
    }

    get isOpenSelectedDisabled() {
        return !this.selectedQuestionnaireId;
    }

    openDefaultQuestionnaire() {
        const defaultQ = this.questionnaires.find(q => q.Is_Default__c);
        if (defaultQ) {
            this.loadQuestionnaire(defaultQ);
        } else if (this.questionnaires.length > 0) {
            this.loadQuestionnaire(this.questionnaires[0]);
        } else {
            this.showToast('Warning', 'No questionnaires available.', 'warning');
        }
    }

    handleQuestionnaireSelect(event) {
        this.selectedQuestionnaireId = event.detail.value;
    }

    openSelectedQuestionnaire() {
        const q = this.questionnaires.find(item => item.Id === this.selectedQuestionnaireId);
        if (q) this.loadQuestionnaire(q);
    }

    loadQuestionnaire(questionnaire) {
    this.selectedQuestionnaire = questionnaire;
    this.isLoading = true;

    getQuestions({ questionnaireId: questionnaire.Id })
        .then(questions => {
            return Promise.all([
                Promise.resolve(questions),
                getExistingResponses({ intakeId: this.recordId, questionnaireId: questionnaire.Id })
            ]);
        })
        .then(([questions, existingResponses]) => {
            const responseMap = {};
            existingResponses.forEach(r => {
                responseMap[r.Question__c] = r.Response_Text__c;
            });
            this.responses = responseMap;
            this.questions = questions;
            this.buildSections(questions);
            this.isLoading = false;

            if (existingResponses.length > 0) {
                this.buildSavedResponsesOutput();
            }
        })
        .catch(error => {
            this.isLoading = false;
            this.showToast('Error', error.body?.message || 'Failed to load questions', 'error');
        });
}

    resetQuestionnaire() {
        this.selectedQuestionnaire = null;
        this.selectedQuestionnaireId = '';
        this.questions = [];
        this.sections = [];
        this.responses = {};
        this.savedResponses = [];
    }

    buildSections(questions) {
        const sectionMap = {};
        questions.forEach(q => {
            const sectionName = q.Section__c || 'General';
            if (!sectionMap[sectionName]) {
                sectionMap[sectionName] = [];
            }
            const enriched = this.enrichQuestion(q);
            sectionMap[sectionName].push(enriched);
        });

        this.sections = Object.keys(sectionMap).map(name => ({
            name,
            questions: sectionMap[name]
        }));
    }

    enrichQuestion(q) {
        const response = this.responses[q.Id] || '';
        return {
            ...q,
            response,
            responseBoolean: response === 'true',
            isVisible: this.checkVisibility(q),
            isText: q.Question_Type__c === 'Text',
            isDate: q.Question_Type__c === 'Date',
            isNumber: q.Question_Type__c === 'Number',
            isPicklist: q.Question_Type__c === 'Picklist',
            isCheckbox: q.Question_Type__c === 'Checkbox',
            isTextarea: q.Question_Type__c === 'Textarea',
            picklistOptions: this.buildPicklistOptions(q.Picklist_Options__c)
        };
    }

    checkVisibility(question) {
        if (!question.Is_Conditional__c || !question.Condition_Question__c) {
            return true; 
        }
        const conditionAnswer = this.responses[question.Condition_Question__c];
        return conditionAnswer === question.Condition_Value__c;
    }

    buildPicklistOptions(optionsString) {
        if (!optionsString) return [];
        return optionsString.split(',').map(opt => ({
            label: opt.trim(),
            value: opt.trim()
        }));
    }

    handleResponseChange(event) {
        const questionId = event.target.dataset.id;
        const value = event.detail.value;
        this.responses = { ...this.responses, [questionId]: value };
        this.refreshVisibility(); 
    }

    handleCheckboxChange(event) {
        const questionId = event.target.dataset.id;
        const value = String(event.detail.checked);
        this.responses = { ...this.responses, [questionId]: value };
        this.refreshVisibility();
    }

    refreshVisibility() {
        this.sections = this.sections.map(section => ({
            ...section,
            questions: section.questions.map(q => ({
                ...q,
                response: this.responses[q.Id] || '',
                responseBoolean: this.responses[q.Id] === 'true',
                isVisible: this.checkVisibility(q)
            }))
        }));
    }

    handleSave() {
        if (!this.validateRequired()) return;

        this.isSaving = true;

        const responsesPayload = Object.entries(this.responses)
            .filter(([, val]) => val !== '')
            .map(([questionId, responseText]) => ({ questionId, responseText }));

        saveResponses({
            intakeId: this.recordId,
            questionnaireId: this.selectedQuestionnaire.Id,
            responsesJson: JSON.stringify(responsesPayload)
        })
        .then(() => {
            this.isSaving = false;
            this.showToast('Success', 'Responses saved successfully!', 'success');
            this.buildSavedResponsesOutput();
        })
        .catch(error => {
            this.isSaving = false;
            this.showToast('Error', error.body?.message || 'Save failed', 'error');
        });
    }

    validateRequired() {
        let isValid = true;
        this.sections.forEach(section => {
            section.questions.forEach(q => {
                if (q.Is_Required__c && q.isVisible && !this.responses[q.Id]) {
                    isValid = false;
                }
            });
        });
        if (!isValid) {
            this.showToast('Validation Error', 'Please fill all required fields.', 'error');
        }
        return isValid;
    }

    buildSavedResponsesOutput() {
        const output = [];
        this.sections.forEach(section => {
            section.questions.forEach(q => {
                if (q.isVisible && this.responses[q.Id]) {
                    output.push({
                        questionId: q.Id,
                        questionText: q.Question_Text__c,
                        responseText: this.responses[q.Id]
                    });
                }
            });
        });
        this.savedResponses = output;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}