import { LightningElement, api } from "lwc";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import markWorkingIfOwner from "@salesforce/apex/IntakeViewTrackerController.markWorkingIfOwner";

export default class IntakeViewTracker extends LightningElement {
    @api recordId;

    _fired = false; // guards against firing more than once per component lifecycle

    connectedCallback() {
        if (this._fired || !this.recordId) return;
        this._fired = true;

        // Fire-and-forget — no UI, no loading state, no error toast.
        // A failure here should never block the user from viewing the record.
        markWorkingIfOwner({ intakeId: this.recordId })
            .then(() => {
                // Tell LDS the record was just updated — all components
                // on this page that are wired to this record will
                // automatically receive the fresh data without a manual refresh.
                getRecordNotifyChange([{ recordId: this.recordId }]);
            })
            .catch((e) => {
                // Log only — never surface to the user
                // eslint-disable-next-line no-console
                console.error("intakeViewTracker: status update failed", e);
            });
    }
}
