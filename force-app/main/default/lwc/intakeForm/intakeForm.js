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
    submitted = false;
    errorMsg = "";
    successMsg = "";

    // dynamic picklist options
    incidentTypeOptions = [];
    injurySeverityOptions = [];
    medicalTreatmentOptions = [];
    insuranceAvailableOptions = [];
    liabilityClarityOptions = [];

    // Stable idempotency token per page load — re-clicks won't double-submit.
    submissionUuid =
        typeof crypto !== "undefined" && crypto.randomUUID
            ? crypto.randomUUID()
            : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

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
            submissionUuid: this.submissionUuid,
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
            this.successMsg = `Thank you — your request was received (reference ${ref}). Our intake team will contact you shortly.`;
            this.submitted = true;
        } catch (e) {
            this.errorMsg =
                (e && e.body && e.body.message) || "Something went wrong. Please try again or call our office.";
        } finally {
            this.submitting = false;
        }
    }
}