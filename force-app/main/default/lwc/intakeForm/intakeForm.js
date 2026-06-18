import { LightningElement, wire } from "lwc";
import createIntake from "@salesforce/apex/IntakeController.createIntake";
import getIntakePicklists from "@salesforce/apex/IntakeController.getIntakePicklists";

export default class IntakeForm extends LightningElement {
    firstName = "";
    lastName = "";
    email = "";
    phone = "";
    country = "";
    dateOfBirth = "";
    incidentType = "";
    incidentDate = "";
    description = "";
    injurySeverity = "";
    medicalTreatmentStatus = "";
    policeCalled = false;
    insuranceAvailable = "";
    liabilityClarity = "";
    consent = false;

    submitting = false;
    errorMsg = "";

    // dynamic picklist options
    incidentTypeOptions = [];
    injurySeverityOptions = [];
    medicalTreatmentOptions = [];
    insuranceAvailableOptions = [];
    liabilityClarityOptions = [];

    @wire(getIntakePicklists)
    wiredPicklists({ data, error }) {
        if (data) {
            this.incidentTypeOptions = data.Incident_Type__c || [];
            this.injurySeverityOptions = data.Injury_Severity__c || [];
            this.medicalTreatmentOptions = data.Medical_Treatment_Status__c || [];
            this.insuranceAvailableOptions = data.Insurance_Available__c || [];
            this.liabilityClarityOptions = data.Liability_Clarity__c || [];
        } else if (error) {
            this.errorMsg = "Could not load form options. Please refresh and try again.";
        }
    }

    get buttonLabel() {
        return this.submitting ? "Submitting…" : "Request my free evaluation";
    }

    handleChange(event) {
        const el = event.target;
        this[el.name] = el.type === "checkbox" ? el.checked : el.value;
    }

    async handleSubmit() {
        this.errorMsg = "";

        if (!this.lastName) {
            this.errorMsg = "Last name is required.";
            return;
        }
        if (!this.email && !this.phone) {
            this.errorMsg = "Please provide an email or phone number.";
            return;
        }
        if (!this.consent) {
            this.errorMsg = "Please accept the consent statement to continue.";
            return;
        }

        this.submitting = true;
        const payload = {
            firstName: this.firstName,
            lastName: this.lastName,
            email: this.email,
            phone: this.phone,
            country: this.country || null,
            dateOfBirth: this.dateOfBirth || null,
            incidentType: this.incidentType || null,
            incidentDate: this.incidentDate || null,
            description: this.description,
            injurySeverity: this.injurySeverity || null,
            medicalTreatmentStatus: this.medicalTreatmentStatus || null,
            policeCalled: this.policeCalled,
            insuranceAvailable: this.insuranceAvailable || null,
            liabilityClarity: this.liabilityClarity || null,
            source: "Web",
            consent: this.consent
        };

        try {
            const ref = await createIntake({ payloadJson: JSON.stringify(payload) });
            // Redirect to the community success page with the Intake Name as a URL param.
            // The success page can read ?id= to display a personalised confirmation.
            window.location.href = `/s/thank-you?id=${ref}`;
        } catch (e) {
            this.errorMsg =
                (e && e.body && e.body.message) || "Something went wrong. Please try again or call our office.";
        }
    }
}