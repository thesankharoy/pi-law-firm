import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

import NEW_AT from '@salesforce/schema/Intake__c.New_Entered_At__c'
import ASSIGNED_AT from '@salesforce/schema/Intake__c.Assigned_Entered_At__c';
import WORKING_AT from '@salesforce/schema/Intake__c.Working_Entered_At__c';
import UNDER_REVIEW_AT from '@salesforce/schema/Intake__c.Under_Review_Entered_At__c';
import QUALIFIED_AT from '@salesforce/schema/Intake__c.Qualified_Entered_At__c';
import RET_SENT_AT from '@salesforce/schema/Intake__c.Retainer_Agreement_Sent_Entered_At__c';
import RET_SIGNED_AT from '@salesforce/schema/Intake__c.Retainer_Agreement_Signed_Entered_At__c';
import TURNED_DOWN_AT from '@salesforce/schema/Intake__c.Turned_Down_Entered_At__c';
import REFERRED_OUT_AT from '@salesforce/schema/Intake__c.Referred_Out_Entered_At__c';
import CONVERTED_AT from '@salesforce/schema/Intake__c.Converted_Entered_At__c';

import TIME_NEW from '@salesforce/schema/Intake__c.Time_in_New__c';
import TIME_OPEN from '@salesforce/schema/Intake__c.Time_in_Open__c';
import TIME_WORKING from '@salesforce/schema/Intake__c.Time_in_Working__c';
import TIME_UNDER_REVIEW from '@salesforce/schema/Intake__c.Time_in_Under_Review__c';
import TIME_QUALIFIED from '@salesforce/schema/Intake__c.Time_in_Qualified__c';
import TIME_RET_SENT from '@salesforce/schema/Intake__c.Time_in_Retainer_Sent__c';
import TIME_RET_SIGNED from '@salesforce/schema/Intake__c.Time_in_Retainer_Signed__c';
import TIME_TURNED_DOWN from '@salesforce/schema/Intake__c.Time_in_Turned_Down__c';
import TIME_REFERRED_OUT from '@salesforce/schema/Intake__c.Time_in_Referred_Out__c';
import TIME_CONVERTED from '@salesforce/schema/Intake__c.Time_in_Converted__c';

import STATUS from '@salesforce/schema/Intake__c.Status__c';

const FIELDS = [
    NEW_AT, ASSIGNED_AT, WORKING_AT, UNDER_REVIEW_AT, QUALIFIED_AT,
    RET_SENT_AT, RET_SIGNED_AT, TURNED_DOWN_AT, REFERRED_OUT_AT, CONVERTED_AT,
    TIME_NEW, TIME_OPEN, TIME_WORKING, TIME_UNDER_REVIEW,
    TIME_QUALIFIED, TIME_RET_SENT, TIME_RET_SIGNED,
    TIME_TURNED_DOWN, TIME_REFERRED_OUT, TIME_CONVERTED,
    STATUS
];

const TERMINAL_STAGES = ['Turned Down', 'Referred Out', 'Converted'];

export default class IntakeStageTimeline extends LightningElement {
  @api recordId;
    
    isLoading = true;
    stageData = [];
    totalTime = '';

    _timerInterval = null; 
    _currentStageEnteredAt = null;
    _staticStageData = [];
    _staticTotalDays = 0;
    _isTerminalStage = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
wiredRecord({ data, error }) {
    if (data) {
        if (this._isTerminalStage && this.stageData.length > 0) {
            return;
        }
        this.processData(data.fields);
        this.isLoading = false;
    } else if (error) {
        console.error('Error fetching record:', error);
        this.isLoading = false;
    }
}

    processData(fields) {
        const currentStatus = fields.Status__c?.value;

        this._isTerminalStage = TERMINAL_STAGES.includes(currentStatus);

        const stageConfig = [
            {
                name: 'New',
                enteredAtField: fields.New_Entered_At__c?.value,
                timeSpentField: fields.Time_in_New__c?.value,
            },
            {
                name: 'Assigned',
                enteredAtField: fields.Assigned_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Open__c?.value,
            },
            {
                name: 'Working',
                enteredAtField: fields.Working_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Working__c?.value,
            },
            {
                name: 'Under Review',
                enteredAtField: fields.Under_Review_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Under_Review__c?.value,
            },
            {
                name: 'Qualified',
                enteredAtField: fields.Qualified_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Qualified__c?.value,
            },
            {
                name: 'Retainer Agreement Sent',
                enteredAtField: fields.Retainer_Agreement_Sent_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Retainer_Sent__c?.value,
            },
            {
                name: 'Retainer Agreement Signed',
                enteredAtField: fields.Retainer_Agreement_Signed_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Retainer_Signed__c?.value,
            },
           {
                name: 'Turned Down',
                enteredAtField: fields.Turned_Down_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Turned_Down__c?.value,
            },
            {
                name: 'Referred Out',
                enteredAtField: fields.Referred_Out_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Referred_Out__c?.value,
            },
            {
                name: 'Converted',
                enteredAtField: fields.Converted_Entered_At__c?.value,
                timeSpentField: fields.Time_in_Converted__c?.value,
            },
        ];

        let staticTotalDays = 0;

        this._staticStageData = stageConfig
            .filter(s => s.enteredAtField) 
            .map(s => {
                const isCurrent = currentStatus === s.name;
                
                if (isCurrent) {
                    this._currentStageEnteredAt = s.enteredAtField;
                }

                let timeSpentStr = '';
                let daysForThisStage = 0;

                if (s.timeSpentField !== null && s.timeSpentField !== undefined) {
                    daysForThisStage = s.timeSpentField;
                    timeSpentStr = this.formatDays(daysForThisStage);
                    if (!isCurrent || this._isTerminalStage) {
                        staticTotalDays += daysForThisStage;
                    }
                }

                return {
                    name: s.name,
                    enteredAt: s.enteredAtField
                        ? new Date(s.enteredAtField).toLocaleString()
                        : null,
                    timeSpent: timeSpentStr,
                    isCurrent,
                    isConverted: s.name === 'Converted' && isCurrent,
                    badgeClass: isCurrent
                        ? 'slds-badge slds-theme_success stage-badge'
                        : 'slds-badge stage-badge'
                };
            });

            this._staticTotalDays = staticTotalDays;

            if (this._isTerminalStage) {
            this.stopTimer();
            this.stageData = [...this._staticStageData];
            this.totalTime = this.formatDays(this._staticTotalDays);
        } else {
            this.updateLiveTime();
            this.startTimer();
        }
    }
     startTimer() {
        this.stopTimer();

        this._timerInterval = setInterval(() => {
            this.updateLiveTime();
        }, 1000);
    }

    stopTimer() {
        if (this._timerInterval) {
            clearInterval(this._timerInterval);
            this._timerInterval = null;
        }
    }

    updateLiveTime() {
        if (!this._currentStageEnteredAt) {
            this.stageData = [...this._staticStageData];
            return;
        }

        const enteredMs = new Date(this._currentStageEnteredAt).getTime();
        const nowMs = Date.now();
        const liveDays = (nowMs - enteredMs) / (1000 * 60 * 60 * 24);
        const liveTimeStr = this.formatDays(liveDays);

        this.stageData = this._staticStageData.map(s => {
            if (s.isCurrent) {
                return { ...s, timeSpent: liveTimeStr };
            }
            return s;
        });

        const totalDays = this._staticTotalDays + liveDays;
        this.totalTime = this.formatDays(totalDays);
    }

    disconnectedCallback() {
        this.stopTimer();
    }

    get isConverted() {
    return this.stageData.some(s => s.name === 'Converted' && s.isCurrent);
}

    formatDays(days) {
        if (days === null || days === undefined || days === '') return '';
        
        const totalSeconds = Math.floor(days * 24 * 60 * 60);
        const d = Math.floor(totalSeconds / 86400);
        const h = Math.floor((totalSeconds % 86400) / 3600);
        const m = Math.floor((totalSeconds % 3600) / 60);
        const s = totalSeconds % 60;

        if (d > 0) return `${d}d ${h}h ${m}m`;
        if (h > 0) return `${h}h ${m}m`;
        if (m > 0) return `${m}m`;
        if (s > 0) return `${s}s`;
        return '< 1s';
    }
}