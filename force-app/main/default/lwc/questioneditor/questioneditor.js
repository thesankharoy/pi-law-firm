import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import getAnswerTypeOptions  from '@salesforce/apex/Questioneditorcontroller.getAnswerTypeOptions';
import saveQuestion          from '@salesforce/apex/Questioneditorcontroller.saveQuestion';
import getQuestion from '@salesforce/apex/Questioneditorcontroller.getQuestion';

const LEGACY_TYPE_MAP = {
    'Text'         : 'STRING',
    'TEXT'         : 'STRING',
    'Textarea'     : 'TEXTAREA',
    'Number'       : 'NUMBER',
    'Decimal'      : 'NUMBER',
    'Boolean'      : 'BOOLEAN',
    'Checkbox'     : 'BOOLEAN',
    'CHECKBOX'     : 'BOOLEAN',
    'Date'         : 'DATE',
    'DateTime'     : 'DATETIME',
    'Picklist'     : 'PICKLIST',
    'SELECT'       : 'PICKLIST',
    'Select'       : 'PICKLIST',
    'Multiselect'  : 'MULTISELECT',
    'MULTIPICKLIST': 'MULTISELECT',
    'Lookup'       : 'LOOKUP',
    'REFERENCE'    : 'LOOKUP',
    'Email'        : 'EMAIL',
    'Phone'        : 'PHONE',
    'Url'          : 'URL',
    'Percent'      : 'PERCENT',
    'Currency'     : 'CURRENCY',
    'Integer'      : 'NUMBER',
};


export default class QuestionEditor extends LightningElement {

    

    @api recordId;
    @api objectApiName;
    @api questionnaireId;

    @track questionLabel    = '';
    @track picklistOptions    = '';
    @track answerTypeOptions = [];
    @track searchTerm        = '';
    @track selectedAnswerType = '';
    @track isDropdownOpen    = false;
    @track isSaving          = false;
    @track loadedQuestionnaireId = '';

    get isEditingExistingQuestion() {
    return this.objectApiName === 'Question__c' && !!this.recordId;
}

    

    get showPicklistOptions() {
    return this.selectedAnswerType === 'PICKLIST'    ||
           this.selectedAnswerType === 'MULTISELECT' ||
           this.selectedAnswerType === 'SELECT'      ||
           this.selectedAnswerType === 'Picklist'    ||
           this.selectedAnswerType === 'Multiselect';
}

    connectedCallback() {
    const answerTypesPromise = getAnswerTypeOptions()
        .then((data) => { this.answerTypeOptions = data || []; })
        .catch((err) => this.showToast('Error', this.errMsg(err), 'error'));

    if (this.isEditingExistingQuestion) {
        Promise.all([answerTypesPromise, this.loadExistingQuestion()])
            .then(() => this.syncSearchTermFromAnswerType());
    
     }
}


    loadExistingQuestion() {
    return getQuestion({ questionId: this.recordId })
        .then((data) => {
            this.questionLabel         = data.Question_Text__c || data.Name || '';
            this.loadedQuestionnaireId = data.Questionnaire__c || '';
            this.picklistOptions       = data.Picklist_Options__c || '';

            // Normalize legacy stored value to canonical new value
            const rawType = data.Question_Type__c || '';
            this.selectedAnswerType = LEGACY_TYPE_MAP[rawType] || rawType;
        })
        .catch((err) => this.showToast('Error', this.errMsg(err), 'error'));
}

   syncSearchTermFromAnswerType() {
    const savedType = (this.selectedAnswerType || '').toUpperCase();
    const match = this.answerTypeOptions.find(
        (o) => o.value.toUpperCase() === savedType || o.label.toUpperCase() === savedType
    );
    if (match) {
        this.searchTerm       = match.label;
        this.selectedAnswerType = match.value; 
    }
}

    get filteredOptions() {
        const term = (this.searchTerm || '').toLowerCase();
        return this.answerTypeOptions
            .filter((o) => o.label.toLowerCase().includes(term))
            .map((o) => ({
                ...o,
                cssClass: o.value === this.selectedAnswerType
                    ? 'option-row option-row_selected'
                    : 'option-row'
            }));
    }

    get hasNoOptions() {
        return this.filteredOptions.length === 0;
    }

    handleLabelChange(e)    { this.questionLabel    = e.detail.value; }
    handlePicklistOptionsChange(e) { this.picklistOptions         = e.detail.value; }

    handleSearchFocus() {
        this.isDropdownOpen = true;
    }

    handleSearchInput(e) {
        this.searchTerm     = e.detail.value;
        this.isDropdownOpen = true;
    }

    handleSearchBlur() {
        setTimeout(() => { this.isDropdownOpen = false; }, 150);
    }

    handleOptionSelect(e) {
        this.selectedAnswerType = e.currentTarget.dataset.value;
        this.searchTerm         = e.currentTarget.dataset.label;
        this.isDropdownOpen     = false;
    }

    handleSave()        { this.doSave(false); }
    handleSaveAndNew()  { this.doSave(true); }

    validate() {
        if (!this.questionLabel || !this.questionLabel.trim()) {
            this.showToast('Error', 'Question Label is required.', 'error');
            return false;
        }
        if (!this.selectedAnswerType) {
            this.showToast('Error', 'Answer Type is required.', 'error');
            return false;
        }
        if (this.showPicklistOptions && !this.picklistOptions.trim()) {
            this.showToast('Error', 'Please enter at least one picklist option.', 'error');
            return false;
        }

        return true;
    }

    doSave(andNew) {
    if (!this.validate()) return;

    this.isSaving = true;
    saveQuestion({
        questionId:      this.isEditingExistingQuestion ? this.recordId : null,
        questionLabel:   this.questionLabel.trim(),
        answerType:      this.selectedAnswerType,
        picklistOptions: this.showPicklistOptions ? this.picklistOptions.trim() : ''
    })
    .then((newId) => {
        this.isSaving = false;
        getRecordNotifyChange([{ recordId: newId }]);
        this.showToast('Success', 'Question saved successfully.', 'success');
        this.dispatchEvent(new CustomEvent('saved', { detail: { questionId: newId, andNew } }));
        if (andNew) this.resetForm();
    })
    .catch((err) => {
        this.isSaving = false;
        this.showToast('Error', this.errMsg(err), 'error');
    });
}

    resetForm() {
        this.questionLabel     = '';
        this.searchTerm        = '';
        this.selectedAnswerType = '';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errMsg(err) {
        return err?.body?.message || err?.message || 'An unexpected error occurred.';
    }
}