import updateIntakeStatus from '@salesforce/apex/IntakeActionsController.updateIntakeStatus';
import { getRecordNotifyChange, getRecord } from 'lightning/uiRecordApi';
import { api, LightningElement, wire } from 'lwc';

export default class IntakeActions extends LightningElement {

    @api recordId;
    isActiveIntake = false;

    @wire(getRecord, { recordId: '$recordId', fields: ['Intake__c.RecordType.DeveloperName'] })
    wiredRecord({ data, error }) {
        if (data) {
            const devName = data.fields.RecordType?.value?.fields?.DeveloperName?.value;
            this.isActiveIntake = devName === 'Active_Intake';
        }
    }

    updateStatus(statusValue) {
        updateIntakeStatus({ recordId: this.recordId, statusValue })
            .then(() => {
                getRecordNotifyChange([{ recordId: this.recordId }]);
            })
            .catch(error => {
                console.error(error);
            });
    }

    handleOpenMatter() { this.updateStatus('Converted'); }
    handleTurnDown()   { this.updateStatus('Turned Down'); }
    handleReferOut()   { this.updateStatus('Referred Out'); }

    handleSendRetainer() {
        // TODO: trigger retainer send logic
    }

    handleLogCall() {
        // TODO: open log-a-call modal or navigate to new Task
    }

    handleScheduleEvent() {
        // TODO: open new Event modal or navigate to NewEvent flow
    }
}