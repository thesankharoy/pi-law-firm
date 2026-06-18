import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";

export default class ThankYouPage extends LightningElement {
    intakeRef = "";

    @wire(CurrentPageReference)
    handlePageRef(pageRef) {
        if (pageRef?.state?.id) {
            this.intakeRef = decodeURIComponent(pageRef.state.id);
        }
    }
}