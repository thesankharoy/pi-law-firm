import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getConsultations from "@salesforce/apex/ConsultationController.getConsultations";
import getAttorneys from "@salesforce/apex/ConsultationController.getAttorneys";
import getIntakeStatus from "@salesforce/apex/ConsultationController.getIntakeStatus";
import checkConflict from "@salesforce/apex/ConsultationController.checkConflict";
import book from "@salesforce/apex/ConsultationController.book";
import reschedule from "@salesforce/apex/ConsultationController.reschedule";
import cancel from "@salesforce/apex/ConsultationController.cancel";
import updateStatus from "@salesforce/apex/ConsultationController.updateStatus";

function pastStatusClass(status) {
    const key = (status || "").toLowerCase().replace(" ", "-");
    return `past-badge past-${key}`;
}

export default class IntakeConsultationBooker extends LightningElement {
    @api recordId;

    @track isLoading = true;
    @track consultations = [];
    @track attorneys = []; // raw — no selection state stored here
    @track isSaving = false;

    // Guard state
    @track isQueueOwned = false;
    @track hasClient = true;

    // Modal state
    @track showModal = false;
    @track showCancelModal = false;
    @track isRescheduleMode = false;
    @track _rescheduleId = null;

    // Form fields
    @track modalType = "Sign-up Consultation";
    @track selectedAttorney = null;
    @track selectedAttorneyId = null; // scalar — drives enrichedAttorneys getter
    @track modalDate = "";
    @track modalTime = "";
    @track modalDuration = 60;
    @track modalMeetingLink = "";
    @track modalLocationStreet = "";
    @track modalLocationCity = "";
    @track modalLocationState = "";
    @track modalLocationPostalCode = "";
    @track modalLocationCountry = "";
    @track modalNotes = "";
    @track modalError = null;
    @track conflictWarning = null;
    @track cancelReason = "";

    // Countdown
    _countdownTimer = null;
    @track countdown = "";

    async connectedCallback() {
        if (!this.recordId) return;
        await Promise.all([this.loadIntakeStatus(), this.loadConsultations(), this.loadAttorneys()]);
        this.startCountdown();
    }

    disconnectedCallback() {
        if (this._countdownTimer) clearInterval(this._countdownTimer);
    }

    // ── Data loading ─────────────────────────────────────────────
    async loadIntakeStatus() {
        try {
            const s = await getIntakeStatus({ intakeId: this.recordId });
            this.isQueueOwned = s.isQueueOwned === true;
            this.hasClient = s.hasClient === true;
        } catch (e) {
            console.error("getIntakeStatus:", this.errMsg(e));
        }
    }

    async loadConsultations() {
        this.isLoading = true;
        try {
            const raw = await getConsultations({ intakeId: this.recordId });
            this.consultations = (raw || []).map((c) => ({
                ...c,
                pastStatusClass: pastStatusClass(c.status)
            }));
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    async loadAttorneys() {
        try {
            const raw = await getAttorneys({ intakeId: this.recordId });
            // Store raw data only — no cardClass; computed in getter
            this.attorneys = (raw || []).map((a) => ({
                ...a,
                initials: a.name
                    .trim()
                    .split(/\s+/)
                    .map((p) => p[0] || "")
                    .join("")
                    .substring(0, 2)
                    .toUpperCase()
            }));
        } catch (e) {
            console.error("loadAttorneys:", this.errMsg(e));
        }
    }

    // ── Countdown ─────────────────────────────────────────────────
    startCountdown() {
        this.refreshCountdown();
        this._countdownTimer = setInterval(() => this.refreshCountdown(), 30000);
    }

    refreshCountdown() {
        const c = this.upcomingConsultation;
        if (!c?.scheduledStartIso) {
            this.countdown = "";
            return;
        }
        const diff = new Date(c.scheduledStartIso) - Date.now();
        if (diff < 0) {
            this.countdown = "Started";
            return;
        }
        const h = Math.floor(diff / 3600000);
        const m = Math.floor((diff % 3600000) / 60000);
        if (h > 48) {
            this.countdown = `In ${Math.floor(h / 24)} days`;
            return;
        }
        if (h >= 24) {
            this.countdown = "Tomorrow";
            return;
        }
        if (h > 0) {
            this.countdown = `In ${h}h ${m}m`;
            return;
        }
        this.countdown = `In ${m} minutes`;
    }

    // ── Guard getters ──────────────────────────────────────────────
    // showNoClientGuard only fires if NOT queue owned (avoid stacking screens)
    get showNoClientGuard() {
        return !this.isQueueOwned && !this.hasClient;
    }
    get showBookingUI() {
        return !this.isQueueOwned && this.hasClient;
    }

    // ── Core getters ───────────────────────────────────────────────
    get upcomingConsultation() {
        return (this.consultations || []).find((c) => c.status === "Scheduled" || c.status === "Confirmed") || null;
    }

    get pastConsultations() {
        return (this.consultations || []).filter((c) => c.status !== "Scheduled" && c.status !== "Confirmed");
    }

    get hasPastConsultations() {
        return this.pastConsultations.length > 0;
    }
    get hasAttorneys() {
        return this.attorneys.length > 0;
    }

    get upcomingAttorneyInitials() {
        const n = this.upcomingConsultation?.attorneyName || "";
        return n
            .trim()
            .split(/\s+/)
            .map((p) => p[0] || "")
            .join("")
            .substring(0, 2)
            .toUpperCase();
    }

    get upcomingStatusBadge() {
        const s = (this.upcomingConsultation?.status || "").toLowerCase().replace(" ", "-");
        return `uc-status-badge status-${s}`;
    }

    get upcomingTypeBadge() {
        return this.upcomingConsultation?.consultationType === "Attorney Callback"
            ? "uc-type-badge callback"
            : "uc-type-badge consult";
    }

    get upcomingCardClass() {
        return this.upcomingConsultation?.status === "Confirmed" ? "uc-card uc-card-confirmed" : "uc-card";
    }

    get todayIso() {
        return new Date().toISOString().substring(0, 10);
    }

    get timeSlots() {
        const slots = [];
        for (let h = 7; h <= 18; h++) {
            for (let m = 0; m < 60; m += 30) {
                const hh = h.toString().padStart(2, "0");
                const mm = m.toString().padStart(2, "0");
                const ampm = h >= 12 ? "PM" : "AM";
                const dh = h > 12 ? h - 12 : h === 0 ? 12 : h;
                slots.push({ value: `${hh}:${mm}`, label: `${dh}:${mm} ${ampm}` });
            }
        }
        return slots;
    }

    get modalTitle() {
        return this.isRescheduleMode ? "Reschedule Consultation" : "Book " + this.modalType;
    }
    get confirmLabel() {
        return this.isRescheduleMode ? "Confirm Reschedule" : "Confirm Booking";
    }
    get showLocation() {
        return this.modalType === "Sign-up Consultation";
    }
    get consultationBtnClass() {
        return this.modalType === "Sign-up Consultation" ? "type-toggle-btn selected" : "type-toggle-btn";
    }
    get callbackBtnClass() {
        return this.modalType === "Attorney Callback" ? "type-toggle-btn selected" : "type-toggle-btn";
    }

    // ── Attorney selection getter ──────────────────────────────────
    // selectedAttorneyId is a scalar @track — changing it triggers this getter
    get enrichedAttorneys() {
        return (this.attorneys || []).map((a) => ({
            ...a,
            cardClass: a.id === this.selectedAttorneyId ? "attorney-card attorney-card-selected" : "attorney-card"
        }));
    }

    // ── Modal open ─────────────────────────────────────────────────
    handleBookClick(e) {
        this.modalType = e.currentTarget.dataset.type;
        this.isRescheduleMode = false;
        this._rescheduleId = null;
        this.resetModalFields();
        this.showModal = true;
    }

    handleReschedule() {
        this.isRescheduleMode = true;
        this._rescheduleId = this.upcomingConsultation.id;
        this.resetModalFields();
        this.showModal = true;
    }

    resetModalFields() {
        const c = this.upcomingConsultation;
        this.selectedAttorney = null;
        this.selectedAttorneyId = null; // clears grid → getter recomputes
        this.modalDate = "";
        this.modalTime = "";
        this.modalDuration = 60;
        this.modalMeetingLink = c?.meetingLink || "";
        this.modalLocationStreet = c?.locationStreet || "";
        this.modalLocationCity = c?.locationCity || "";
        this.modalLocationState = c?.locationState || "";
        this.modalLocationPostalCode = c?.locationPostalCode || "";
        this.modalLocationCountry = c?.locationCountry || "";
        this.modalNotes = c?.notes || "";
        this.modalError = null;
        this.conflictWarning = null;
    }

    closeModal() {
        this.showModal = false;
    }
    closeCancelModal() {
        this.showCancelModal = false;
    }
    handleModalBackdropClick() {
        this.closeModal();
    }
    stopProp(e) {
        e.stopPropagation();
    }

    // ── Form handlers ──────────────────────────────────────────────
    handleTypeSelect(e) {
        this.modalType = e.currentTarget.dataset.type;
    }

    handleAttorneySelect(e) {
        const id = e.currentTarget.dataset.id;
        // Toggle: click selected → deselect
        if (this.selectedAttorneyId === id) {
            this.selectedAttorneyId = null;
            this.selectedAttorney = null;
        } else {
            this.selectedAttorneyId = id;
            this.selectedAttorney = this.attorneys.find((a) => a.id === id) || null;
        }
        this.triggerConflictCheck();
    }

    handleDateChange(e) {
        this.modalDate = e.target.value;
        this.triggerConflictCheck();
    }
    handleTimeChange(e) {
        this.modalTime = e.target.value;
        this.triggerConflictCheck();
    }
    handleDurationChange(e) {
        this.modalDuration = parseInt(e.target.value, 10);
    }
    handleMeetingLinkInput(e) {
        this.modalMeetingLink = e.target.value;
    }
    handleNotesInput(e) {
        this.modalNotes = e.target.value;
    }
    handleCancelReasonChange(e) {
        this.cancelReason = e.target.value;
    }

    handleLocationChange(e) {
        this.modalLocationStreet = e.detail.street || "";
        this.modalLocationCity = e.detail.city || "";
        this.modalLocationState = e.detail.province || "";
        this.modalLocationPostalCode = e.detail.postalCode || "";
        this.modalLocationCountry = e.detail.country || "";
    }

    handleCancelClick() {
        this.showCancelModal = true;
    }
    async handleMarkComplete() {
        await this.setStatus("Completed");
    }
    async handleMarkNoShow() {
        await this.setStatus("No Show");
    }

    // ── Conflict check ─────────────────────────────────────────────
    _conflictTimer = null;
    triggerConflictCheck() {
        clearTimeout(this._conflictTimer);
        if (!this.selectedAttorneyId || !this.modalDate || !this.modalTime) return;
        this._conflictTimer = setTimeout(async () => {
            try {
                const res = await checkConflict({
                    attorneyId: this.selectedAttorneyId,
                    startIso: `${this.modalDate}T${this.modalTime}:00`,
                    durationMinutes: this.modalDuration
                });
                this.conflictWarning = res.hasConflict ? res.conflictLabel : null;
            } catch (e) {
                /* silent */
            }
        }, 600);
    }

    // ── Confirm booking ────────────────────────────────────────────
    async handleConfirmBooking() {
        const err = this.validateModal();
        if (err) {
            this.modalError = err;
            return;
        }
        this.isSaving = true;
        try {
            if (this.isRescheduleMode) {
                await reschedule({
                    consultationId: this._rescheduleId,
                    newStartIso: `${this.modalDate}T${this.modalTime}:00`,
                    durationMinutes: this.modalDuration
                });
                this.toast("Rescheduled", "Updated invite sent.", "success");
            } else {
                await book({
                    requestJson: JSON.stringify({
                        intakeId: this.recordId,
                        consultationType: this.modalType,
                        attorneyIds: [this.selectedAttorneyId],
                        startDateTimeIso: `${this.modalDate}T${this.modalTime}:00`,
                        durationMinutes: this.modalDuration,
                        meetingLink: this.modalMeetingLink,
                        locationStreet: this.modalLocationStreet,
                        locationCity: this.modalLocationCity,
                        locationState: this.modalLocationState,
                        locationPostalCode: this.modalLocationPostalCode,
                        locationCountry: this.modalLocationCountry,
                        notes: this.modalNotes
                    })
                });
                this.toast("Booked", "Consultation confirmed — calendar invite sent.", "success");
            }
            this.showModal = false;
            await this.loadConsultations();
            this.refreshCountdown();
        } catch (e) {
            this.modalError = this.errMsg(e);
        } finally {
            this.isSaving = false;
        }
    }

    // ── Cancel ─────────────────────────────────────────────────────
    async handleConfirmCancel() {
        this.isSaving = true;
        try {
            await cancel({
                consultationId: this.upcomingConsultation.id,
                reason: this.cancelReason
            });
            this.showCancelModal = false;
            this.toast("Cancelled", "Cancellation notice sent.", "success");
            await this.loadConsultations();
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isSaving = false;
        }
    }

    // ── Status ─────────────────────────────────────────────────────
    async setStatus(newStatus) {
        try {
            await updateStatus({ consultationId: this.upcomingConsultation.id, newStatus });
            this.toast("Updated", `Marked as ${newStatus}.`, "success");
            await this.loadConsultations();
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        }
    }

    // ── Validation ─────────────────────────────────────────────────
    validateModal() {
        if (!this.isRescheduleMode && !this.selectedAttorneyId) return "Please select an attorney.";
        if (!this.modalDate) return "Please select a date.";
        if (!this.modalTime) return "Please select a time.";
        if (new Date(`${this.modalDate}T${this.modalTime}:00`) <= new Date())
            return "Please select a future date and time.";
        return null;
    }

    toast(t, m, v) {
        this.dispatchEvent(new ShowToastEvent({ title: t, message: m, variant: v }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}
