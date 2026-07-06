import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

import NEW_AT from '@salesforce/schema/Intake__c.New_Entered_At__c'
import ASSIGNED_AT from '@salesforce/schema/Intake__c.Assigned_Entered_At__c';
import WORKING_AT from '@salesforce/schema/Intake__c.Working_Entered_At__c';
import UNDER_REVIEW_AT from '@salesforce/schema/Intake__c.Under_Review_Entered_At__c';
import DEFERRED_AT from '@salesforce/schema/Intake__c.Deferred_Entered_At__c';
import RET_SENT_AT from '@salesforce/schema/Intake__c.Retainer_Agreement_Sent_Entered_At__c';
import RET_SIGNED_AT from '@salesforce/schema/Intake__c.Retainer_Agreement_Signed_Entered_At__c';
import TURNED_DOWN_AT from '@salesforce/schema/Intake__c.Turned_Down_Entered_At__c';
import REFERRED_OUT_AT from '@salesforce/schema/Intake__c.Referred_Out_Entered_At__c';
import CONVERTED_AT from '@salesforce/schema/Intake__c.Converted_Entered_At__c';

import TIME_NEW from '@salesforce/schema/Intake__c.Time_in_New__c';
import TIME_OPEN from '@salesforce/schema/Intake__c.Time_in_Open__c';
import TIME_WORKING from '@salesforce/schema/Intake__c.Time_in_Working__c';
import TIME_UNDER_REVIEW from '@salesforce/schema/Intake__c.Time_in_Under_Review__c';
import TIME_DEFERRED from '@salesforce/schema/Intake__c.Time_in_Deferred__c';
import TIME_RET_SENT from '@salesforce/schema/Intake__c.Time_in_Retainer_Sent__c';
import TIME_RET_SIGNED from '@salesforce/schema/Intake__c.Time_in_Retainer_Signed__c';
import TIME_TURNED_DOWN from '@salesforce/schema/Intake__c.Time_in_Turned_Down__c';
import TIME_REFERRED_OUT from '@salesforce/schema/Intake__c.Time_in_Referred_Out__c';
import TIME_CONVERTED from '@salesforce/schema/Intake__c.Time_in_Converted__c';

import STATUS from '@salesforce/schema/Intake__c.Status__c';

const FIELDS = [
    NEW_AT, ASSIGNED_AT, WORKING_AT, UNDER_REVIEW_AT, DEFERRED_AT,
    RET_SENT_AT, RET_SIGNED_AT, TURNED_DOWN_AT, REFERRED_OUT_AT, CONVERTED_AT,
    TIME_NEW, TIME_OPEN, TIME_WORKING, TIME_UNDER_REVIEW,
    TIME_DEFERRED, TIME_RET_SENT, TIME_RET_SIGNED,
    TIME_TURNED_DOWN, TIME_REFERRED_OUT, TIME_CONVERTED,
    STATUS
];

const TERMINAL_STAGES = ['Turned Down', 'Referred Out', 'Converted'];

// ─── UI config per stage ──────────────────────────────────────────────────────
const STAGE_UI = {
    // 'New':                       { iconName: 'utility:play',        iconKey: 'new'         },
    'Assigned':                  { iconName: 'utility:user',         iconKey: 'assigned'    },
    'Working':                   { iconName: 'utility:settings',     iconKey: 'working'     },
    'Under Review':              { iconName: 'utility:preview',      iconKey: 'review'      },
    'Deferred':                  { iconName: 'utility:check',        iconKey: 'deferred'   },
    'Retainer Agreement Sent':   { iconName: 'utility:email',        iconKey: 'ret-sent'    },
    'Retainer Agreement Signed': { iconName: 'utility:edit',         iconKey: 'ret-signed'  },
    'Turned Down':               { iconName: 'utility:close',        iconKey: 'turned-down' },
    'Referred Out':              { iconName: 'utility:forward',      iconKey: 'referred'    },
    'Converted':                 { iconName: 'utility:check',        iconKey: 'converted'   },
};

export default class IntakeStageTimeline extends LightningElement {
    @api recordId;

    isLoading = true;

    // "Heartbeat" field. The interval below reassigns ONLY this primitive
    // every second. stageData / totalTime / isConverted are getters that
    // read it, so LWC's reactivity engine tracks the dependency and
    // re-renders the template automatically on every tick - no manual
    // array rebuilding/reassignment timing to get wrong, and nothing that
    // can get "stuck" until a hard refresh.
    now = Date.now();

    _timerInterval = null;
    _currentStageEnteredAt = null;
    _staticStageData = [];
    _staticTotalDays = 0;
    _isTerminalStage = false;
    _firstEnteredAt = null;
    _currentStageName = '';

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            if (this._isTerminalStage && this._staticStageData.length > 0) {
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
        this._currentStageEnteredAt = null;
        this._currentStageName = currentStatus || '';

        const stageConfig = [
            // { name: 'New', enteredAtField: fields.New_Entered_At__c?.value, timeSpentField: fields.Time_in_New__c?.value },
            { name: 'Assigned', enteredAtField: fields.Assigned_Entered_At__c?.value, timeSpentField: fields.Time_in_Open__c?.value },
            { name: 'Working', enteredAtField: fields.Working_Entered_At__c?.value, timeSpentField: fields.Time_in_Working__c?.value },
            { name: 'Under Review', enteredAtField: fields.Under_Review_Entered_At__c?.value, timeSpentField: fields.Time_in_Under_Review__c?.value },
            { name: 'Deferred', enteredAtField: fields.Deferred_Entered_At__c?.value, timeSpentField: fields.Time_in_Deferred__c?.value },
            { name: 'Retainer Agreement Sent', enteredAtField: fields.Retainer_Agreement_Sent_Entered_At__c?.value, timeSpentField: fields.Time_in_Retainer_Sent__c?.value },
            { name: 'Retainer Agreement Signed', enteredAtField: fields.Retainer_Agreement_Signed_Entered_At__c?.value, timeSpentField: fields.Time_in_Retainer_Signed__c?.value },
            { name: 'Turned Down', enteredAtField: fields.Turned_Down_Entered_At__c?.value, timeSpentField: fields.Time_in_Turned_Down__c?.value },
            { name: 'Referred Out', enteredAtField: fields.Referred_Out_Entered_At__c?.value, timeSpentField: fields.Time_in_Referred_Out__c?.value },
            { name: 'Converted', enteredAtField: fields.Converted_Entered_At__c?.value, timeSpentField: fields.Time_in_Converted__c?.value },
        ];

        let staticTotalDays = 0;
        let firstEnteredAt = null;

        this._staticStageData = stageConfig
            .map((s, idx) => {
                const isCurrent = currentStatus === s.name;
                const isReached = !!s.enteredAtField;
                const isCompleted = isReached && !isCurrent;

                if (isCurrent) {
                    this._currentStageEnteredAt = s.enteredAtField;
                }

                // Track earliest entered-at for "Started On"
                if (isReached && !firstEnteredAt) {
                    firstEnteredAt = s.enteredAtField;
                }

                let staticDays = null;
                const raw = s.timeSpentField;

                if (raw !== null && raw !== undefined && raw !== '') {
                    // Defensive Number() coercion. getRecord can hand back
                    // formula Number fields as strings depending on the
                    // field's metadata, and `0 + "1.5"` silently does
                    // STRING CONCATENATION in JS instead of addition -
                    // which corrupts every running total computed after it
                    // and ultimately turns the "Total Time" into NaN.
                    staticDays = Number(raw);
                    if (!isCurrent || this._isTerminalStage) {
                        staticTotalDays += staticDays;
                    }
                }

                // ─── Derive UI properties ───────────────────────────────
                const ui = STAGE_UI[s.name] || { iconName: 'utility:record', iconKey: 'new' };

                // Status label + badge class
                let statusLabel = 'Pending';
                let statusBadgeClass = 'status-badge status-badge--pending';
                if (isCurrent && TERMINAL_STAGES.includes(s.name)) {
                    statusLabel = 'Terminated/Closed';
                    statusBadgeClass = 'status-badge status-badge--terminated';
                } else if (isCurrent) {
                    statusLabel = 'In Progress';
                    statusBadgeClass = 'status-badge status-badge--inprogress';
                } else if (isCompleted) {
                    statusLabel = 'Completed';
                    statusBadgeClass = 'status-badge status-badge--completed';
                }

                // Row highlight class
                let rowClass = 'row--pending';
                if (isCurrent) rowClass = 'row--inprogress';
                else if (isCompleted) rowClass = 'row--completed';

                // Icon bubble class
                const iconWrapBase = 'stage-icon-wrap';
                const iconWrapClass = isReached
                    ? `${iconWrapBase} stage-icon-wrap--${ui.iconKey}`
                    : `${iconWrapBase} stage-icon-wrap--pending`;

                return {
                    name: s.name,
                    enteredAt: s.enteredAtField ? new Date(s.enteredAtField).toLocaleString() : null,
                    isCurrent,
                    isCompleted,
                    isReached,
                    isLast: idx === stageConfig.length - 1,
                    isConverted: s.name === 'Converted' && isCurrent,
                    // legacy badge (kept for backward compat, not used in new template)
                    badgeClass: isCurrent
                        ? 'slds-badge slds-theme_success stage-badge'
                        : 'slds-badge stage-badge',
                    staticDays,
                    // new UI fields
                    statusLabel,
                    statusBadgeClass,
                    rowClass,
                    iconName: ui.iconName,
                    iconWrapClass,
                    iconVariant: 'inverse',
                };
            });

        this._staticTotalDays = staticTotalDays;
        this._firstEnteredAt = firstEnteredAt;

        if (this._isTerminalStage) {
            this.stopTimer();
        } else {
            this.startTimer();
        }

        // Force an immediate recompute instead of waiting up to 1s for the
        // first tick.
        this.now = Date.now();
    }

    startTimer() {
        if (this._timerInterval) {
            return; // already ticking - don't stack intervals
        }
        this._timerInterval = setInterval(() => {
            this.now = Date.now();
        }, 1000);
    }

    stopTimer() {
        if (this._timerInterval) {
            clearInterval(this._timerInterval);
            this._timerInterval = null;
        }
    }

    disconnectedCallback() {
        this.stopTimer();
    }

    // ─── Existing getters (logic unchanged) ──────────────────────────────────

    get stageData() {
        return this._staticStageData.map(s => {
            let timeSpent = '';

            if (s.isCurrent && !this._isTerminalStage && this._currentStageEnteredAt) {
                const liveDays = (this.now - new Date(this._currentStageEnteredAt).getTime()) / (1000 * 60 * 60 * 24);
                timeSpent = this.formatDays(liveDays);
            } else if (s.staticDays !== null) {
                timeSpent = this.formatDays(s.staticDays);
            }

            // Add a time class for coloring the time value cell
            const timeClass = s.isCurrent && !this._isTerminalStage
                ? 'time-value--inprogress'
                : s.isCompleted ? 'time-value--completed' : '';

            return { ...s, timeSpent, timeClass };
        });
    }

    get totalTime() {
        let totalDays = this._staticTotalDays;

        if (!this._isTerminalStage && this._currentStageEnteredAt) {
            const liveDays = (this.now - new Date(this._currentStageEnteredAt).getTime()) / (1000 * 60 * 60 * 24);
            totalDays += liveDays;
        }

        return this.formatDays(totalDays);
    }

    get isConverted() {
        return this._staticStageData.some(s => s.name === 'Converted' && s.isCurrent);
    }

    // ─── New UI-only getters (no business logic) ──────────────────────────────

    get isTerminalStage() {
        return this._isTerminalStage;
    }

    get currentStageName() {
        return this._currentStageName || '—';
    }

    get currentStageTime() {
        if (!this._currentStageEnteredAt || this._isTerminalStage) return '—';
        const liveDays = (this.now - new Date(this._currentStageEnteredAt).getTime()) / (1000 * 60 * 60 * 24);
        return this.formatDays(liveDays);
    }

    get startedOn() {
        if (!this._firstEnteredAt) return '—';
        return new Date(this._firstEnteredAt).toLocaleString();
    }

    // ─── Utility ─────────────────────────────────────────────────────────────

    formatDays(days) {
        if (days === null || days === undefined || days === '' || Number.isNaN(days)) return '';

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