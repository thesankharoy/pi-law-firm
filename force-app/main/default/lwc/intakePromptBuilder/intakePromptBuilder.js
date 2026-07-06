import { LightningElement, api, track } from 'lwc';
import getIntakePrompt from '@salesforce/apex/IntakePromptBuilder.getIntakePrompt';

const FIELD_QUESTIONS = {
    Incident_Type__c:            'What type of incident occurred? (e.g., auto accident, slip and fall, workplace injury)',
    Injury_Severity__c:          'How severe are the injuries? (e.g., minor, moderate, severe, catastrophic)',
    Medical_Treatment_Status__c: 'Has the client received medical treatment? If so, what is the current status?',
    Police_Report_Filed__c:      'Was a police report filed? If yes, do you have the report number?',
    Incident_Age__c:             'When did the incident occur? (date or approximate time frame)',
    Insurance_Available__c:      'Is insurance coverage available? (client\'s own policy or third-party)',
    Liability_Clarity__c:        'How clear is the liability? Is fault established or disputed?'
};

const FIELD_LABELS = {
    Incident_Type__c:            'Incident Type',
    Injury_Severity__c:          'Injury Severity',
    Medical_Treatment_Status__c: 'Medical Treatment Status',
    Police_Report_Filed__c:      'Police Report Filed',
    Incident_Age__c:             'Incident Age',
    Insurance_Available__c:      'Insurance Available',
    Liability_Clarity__c:        'Liability Clarity'
};

const TOTAL_FIELDS = Object.keys(FIELD_LABELS).length;

export default class IntakePromptBuilder extends LightningElement {
    @api recordId;

    @track isLoading = false;
    @track hasError = false;
    @track errorMessage = '';
    @track allFilled = false;
    @track missingCount = 0;
    @track missingFields = [];

    connectedCallback() {
        this.loadPrompt();
    }

    handleRefresh() {
        this.loadPrompt();
    }

    loadPrompt() {
        this.isLoading = true;
        this.hasError = false;
        this.allFilled = false;
        this.missingCount = 0;
        this.missingFields = [];

        getIntakePrompt({ intakeId: this.recordId })
            .then(result => {
                this.allFilled = result.allFilled;
                this.missingCount = result.missingCount;
                this.missingFields = this.parseMissingFields(result.prompt);
            })
            .catch(error => {
                this.hasError = true;
                this.errorMessage = error.body?.message || 'An error occurred while loading the intake checklist.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    parseMissingFields(prompt) {
        const missing = [];
        for (const [apiName, label] of Object.entries(FIELD_LABELS)) {
            if (prompt && prompt.includes(label)) {
                missing.push({ apiName, label, question: FIELD_QUESTIONS[apiName] });
            }
        }
        return missing;
    }

    get hasContent() {
        return !this.isLoading && !this.hasError;
    }

    get hasMissingFields() {
        return this.hasContent && !this.allFilled && this.missingFields.length > 0;
    }

    get completedCount() {
        return TOTAL_FIELDS - this.missingFields.length;
    }

    get totalFields() {
        return TOTAL_FIELDS;
    }

    get progressPercent() {
        return Math.round((this.completedCount / TOTAL_FIELDS) * 100);
    }

    get progressStyle() {
        return `width:${this.progressPercent}%;`;
    }

    get progressLabel() {
        return `${this.completedCount} of ${TOTAL_FIELDS} captured`;
    }

    // Missing items — surfaced first as action cards with the question to ask.
    get missingItems() {
        return this.missingFields.map(field => ({
            apiName: field.apiName,
            label: field.label,
            question: field.question
        }));
    }

    // Captured items — everything not in the missing set, in field order.
    get capturedItems() {
        const missingApis = new Set(this.missingFields.map(f => f.apiName));
        return Object.keys(FIELD_LABELS)
            .filter(apiName => !missingApis.has(apiName))
            .map(apiName => ({ apiName, label: FIELD_LABELS[apiName] }));
    }
}