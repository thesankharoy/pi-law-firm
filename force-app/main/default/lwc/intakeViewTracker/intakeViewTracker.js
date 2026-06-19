import { LightningElement, api } from "lwc";
import markWorkingIfOwner from "@salesforce/apex/IntakeViewTrackerController.markWorkingIfOwner";

export default class IntakeViewTracker extends LightningElement {
    @api recordId;

    _fired = false; // guards against firing more than once per component lifecycle

    connectedCallback() {
        if (this._fired || !this.recordId) return;
        this._fired = true;

        // Fire-and-forget — no UI, no loading state, no error toast.
        // A failure here should never block the user from viewing the record.
        markWorkingIfOwner({ intakeId: this.recordId }).catch((e) => {
            // Log only — never surface to the user
            // eslint-disable-next-line no-console
            console.error("intakeViewTracker: status update failed", e);
        });
    }
}
