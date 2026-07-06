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

function initialsFor(name) {
    return (name || "")
        .trim()
        .split(/\s+/)
        .map((p) => p[0] || "")
        .join("")
        .substring(0, 2)
        .toUpperCase();
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
    @track _cancelTargetId = null;

    // Form fields
    @track modalType = "Sign-up Consultation";
    @track selectedAttorneyIds = [];
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

    // Countdown — NEW approach: instead of tracking one countdown
    // string for a single consultation, _nowTick is bumped every 30s
    // and the upcomingConsultations getter recomputes a fresh
    // countdown per card from that tick + live Date.now().
    @track _nowTick = Date.now();
    _countdownTimer = null;

    // Textarea reactivity fix — same pattern used elsewhere in this
    // codebase (see intakeDripManager). LWC does not reactively sync a
    // <textarea>'s DOM value after first render, so re-opening this
    // modal for Reschedule with pre-filled notes never showed them
    // without this imperative sync in renderedCallback.
    _needsNotesSync = false;

    async connectedCallback() {
        if (!this.recordId) return;
        await Promise.all([this.loadIntakeStatus(), this.loadConsultations(), this.loadAttorneys()]);
        this.startCountdownTicker();
    }

    disconnectedCallback() {
        if (this._countdownTimer) clearInterval(this._countdownTimer);
    }

    renderedCallback() {
        if (this._needsNotesSync && this.showModal) {
            const ta = this.template.querySelector('textarea[data-field="notes"]');
            if (ta) {
                ta.value = this.modalNotes || "";
                this._needsNotesSync = false;
            }
        }
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
            this.consultations = (raw || []).map((c) => {
                const attorneys = (c.attorneys || []).map((a) => ({
                    ...a,
                    initials: initialsFor(a.name)
                }));
                return {
                    ...c,
                    pastStatusClass: pastStatusClass(c.status),
                    attorneys,
                    attorneyNames: attorneys.length ? attorneys.map((a) => a.name).join(", ") : "—"
                };
            });
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    async loadAttorneys() {
        try {
            const raw = await getAttorneys({ intakeId: this.recordId });
            this.attorneys = (raw || []).map((a) => ({
                ...a,
                initials: initialsFor(a.name)
            }));
        } catch (e) {
            console.error("loadAttorneys:", this.errMsg(e));
        }
    }

    // ── Countdown ticker ─────────────────────────────────────────
    startCountdownTicker() {
        this._countdownTimer = setInterval(() => {
            this._nowTick = Date.now();
        }, 30000);
    }

    // Reads _nowTick so the calling getter (upcomingConsultations)
    // re-evaluates every time the ticker advances, keeping every
    // card's countdown fresh without a separate tracked value per card.
    computeCountdown(iso) {
        // eslint-disable-next-line no-unused-expressions
        this._nowTick;
        if (!iso) return "";
        const diff = new Date(iso) - Date.now();
        if (diff < 0) return "Started";
        const h = Math.floor(diff / 3600000);
        const m = Math.floor((diff % 3600000) / 60000);
        if (h > 48) return `In ${Math.floor(h / 24)} days`;
        if (h >= 24) return "Tomorrow";
        if (h > 0) return `In ${h}h ${m}m`;
        return `In ${m} minutes`;
    }

    // ── Guard getters ──────────────────────────────────────────────
    get showNoClientGuard() {
        return !this.isQueueOwned && !this.hasClient;
    }
    get showBookingUI() {
        return !this.isQueueOwned && this.hasClient;
    }

    // ── Core getters — PLURAL now, was a single upcomingConsultation ──
    // PREVIOUSLY only the single soonest Scheduled/Confirmed
    // consultation was ever shown, and the Book buttons were hidden
    // entirely once that one slot was filled — there was no way to
    // book a second, different-time consultation. Fixed: every
    // upcoming consultation is now shown as its own card, and a
    // compact "Book another" row is always available alongside them.
    get upcomingConsultations() {
        return (this.consultations || [])
            .filter((c) => c.status === "Scheduled" || c.status === "Confirmed")
            .map((c) => ({
                ...c,
                statusBadgeClass: `uc-status-badge status-${(c.status || "").toLowerCase().replace(" ", "-")}`,
                typeBadgeClass:
                    c.consultationType === "Attorney Callback" ? "uc-type-badge callback" : "uc-type-badge consult",
                cardClass: c.status === "Confirmed" ? "uc-card uc-card-confirmed" : "uc-card",
                attorneyRoleLabel: (c.attorneys?.length || 0) > 1 ? "Attorneys" : "Attorney",
                countdownLabel: this.computeCountdown(c.scheduledStartIso)
            }))
            .sort((a, b) => new Date(a.scheduledStartIso) - new Date(b.scheduledStartIso));
    }

    get hasUpcomingConsultations() {
        return this.upcomingConsultations.length > 0;
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

    // ── Multi-select attorney getters ─────────────────────────────
    get enrichedAttorneys() {
        const selectedSet = new Set(this.selectedAttorneyIds);
        return (this.attorneys || []).map((a) => ({
            ...a,
            isSelected: selectedSet.has(a.id),
            cardClass: selectedSet.has(a.id) ? "attorney-card attorney-card-selected" : "attorney-card"
        }));
    }

    get hasSelectedAttorneys() {
        return this.selectedAttorneyIds.length > 0;
    }

    get selectionCountLabel() {
        const n = this.selectedAttorneyIds.length;
        if (n === 0) return "";
        return n === 1 ? "1 selected" : `${n} selected`;
    }

    // ── Modal open ─────────────────────────────────────────────────
    handleBookClick(e) {
        this.modalType = e.currentTarget.dataset.type;
        this.isRescheduleMode = false;
        this._rescheduleId = null;
        this.resetModalFields(null);
        this.showModal = true;
    }

    // Now targets a SPECIFIC consultation via data-id, seeds the modal
    // from that consultation's own fields (including type — PREVIOUSLY
    // modalType was never reset here, so rescheduling an Attorney
    // Callback could incorrectly show/hide the Location field based on
    // stale state from whatever was last booked).
    handleReschedule(e) {
        const id = e.currentTarget.dataset.id;
        const target = this.upcomingConsultations.find((c) => c.id === id);
        this.modalType = target?.consultationType || "Sign-up Consultation";
        this.isRescheduleMode = true;
        this._rescheduleId = id;
        this.resetModalFields(target);
        this.showModal = true;
    }

    resetModalFields(c) {
        this.selectedAttorneyIds = []; // clears grid → getter recomputes
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
        this._needsNotesSync = true; // triggers renderedCallback textarea sync
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
        const idx = this.selectedAttorneyIds.indexOf(id);
        if (idx === -1) {
            this.selectedAttorneyIds = [...this.selectedAttorneyIds, id];
        } else {
            this.selectedAttorneyIds = this.selectedAttorneyIds.filter((x) => x !== id);
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

    handleCancelClick(e) {
        this._cancelTargetId = e.currentTarget.dataset.id;
        this.showCancelModal = true;
    }
    async handleMarkComplete(e) {
        await this.setStatus("Completed", e.currentTarget.dataset.id);
    }
    async handleMarkNoShow(e) {
        await this.setStatus("No Show", e.currentTarget.dataset.id);
    }

    // ── Conflict check — checks EVERY selected attorney ─────────────
    _conflictTimer = null;
    triggerConflictCheck() {
        clearTimeout(this._conflictTimer);
        if (!this.selectedAttorneyIds.length || !this.modalDate || !this.modalTime) {
            this.conflictWarning = null;
            return;
        }
        this._conflictTimer = setTimeout(async () => {
            try {
                const startIso = `${this.modalDate}T${this.modalTime}:00`;
                const results = await Promise.all(
                    this.selectedAttorneyIds.map((id) =>
                        checkConflict({
                            attorneyId: id,
                            startIso,
                            durationMinutes: this.modalDuration
                        }).then((res) => ({ id, res }))
                    )
                );
                const conflicted = results.find((r) => r.res.hasConflict);
                if (conflicted) {
                    const name = this.attorneys.find((a) => a.id === conflicted.id)?.name || "Selected attorney";
                    this.conflictWarning = `${name}: ${conflicted.res.conflictLabel}`;
                } else {
                    this.conflictWarning = null;
                }
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
                        attorneyIds: this.selectedAttorneyIds,
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
                const n = this.selectedAttorneyIds.length;
                this.toast(
                    "Booked",
                    `Confirmed — calendar invite sent to ${n} attorney${n > 1 ? "s" : ""}.`,
                    "success"
                );
            }
            this.showModal = false;
            await this.loadConsultations();
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
                consultationId: this._cancelTargetId,
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
    async setStatus(newStatus, consultationId) {
        try {
            await updateStatus({ consultationId, newStatus });
            this.toast("Updated", `Marked as ${newStatus}.`, "success");
            await this.loadConsultations();
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        }
    }

    // ── Validation ─────────────────────────────────────────────────
    validateModal() {
        if (!this.isRescheduleMode && this.selectedAttorneyIds.length === 0)
            return "Please select at least one attorney.";
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