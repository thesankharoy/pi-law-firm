/**
 * The closed taxonomy and the validation source of truth (Guardrail 1).
 * To change the taxonomy, edit the matching picklist values AND these sets together.
 *
 * Fault category is derived deterministically from the reason here — it is never
 * trusted from the model, so "how much was our fault" is always reproducible.
 */
public class WinLossTaxonomy {

    public static final String UNCLASSIFIED = 'Unclassified';
    public static final String OTHER_OBJECTION = 'Other';
    public static final String FAULT_UNKNOWN = 'Unknown';

    public static final Set<String> REASONS = new Set<String>{
        'Fee_Or_Cost_Concern', 'Chose_Another_Firm', 'Case_Declined_Merits', 'Statute_Expired',
        'Insufficient_Injury_Or_Damages', 'No_Clear_Liability', 'Already_Represented', 'Wanted_Self_Handle',
        'Slow_Response_Or_Experience', 'Lost_Contact_Ghosted', 'Trust_Or_Comfort', 'Conflict_Of_Interest',
        'Referred_Out_Intentional', 'Unclassified'
    };

    public static final Set<String> OBJECTIONS = new Set<String>{
        'Fee_Percentage', 'Time_To_Resolution', 'Will_I_Owe_Anything', 'Why_Your_Firm', 'Case_Worth_Question',
        'Need_To_Think', 'Family_Decision', 'Distrust', 'Already_Talked_To_Firm', 'Process_Confusion', 'Other'
    };

    private static final Map<String, String> REASON_TO_FAULT = new Map<String, String>{
        'Slow_Response_Or_Experience'     => 'Process',
        'Lost_Contact_Ghosted'            => 'Process',
        'Trust_Or_Comfort'                => 'Process',
        'Case_Declined_Merits'            => 'Case_Merits',
        'Statute_Expired'                 => 'Case_Merits',
        'Insufficient_Injury_Or_Damages'  => 'Case_Merits',
        'No_Clear_Liability'              => 'Case_Merits',
        'Conflict_Of_Interest'            => 'Case_Merits',
        'Referred_Out_Intentional'        => 'Case_Merits',
        'Fee_Or_Cost_Concern'             => 'Client_Choice',
        'Chose_Another_Firm'              => 'Client_Choice',
        'Already_Represented'             => 'Client_Choice',
        'Wanted_Self_Handle'              => 'Client_Choice'
    };

    /** Guardrail 1: snap an off-taxonomy reason to the safe default. */
    public static String safeReason(String r) {
        return (r != null && REASONS.contains(r)) ? r : UNCLASSIFIED;
    }

    /** Guardrail 1: snap an off-taxonomy objection to Other. */
    public static String safeObjection(String o) {
        return (o != null && OBJECTIONS.contains(o)) ? o : OTHER_OBJECTION;
    }

    /** Deterministic fault category for a (already-validated) reason. */
    public static String faultFor(String reason) {
        String f = REASON_TO_FAULT.get(reason);
        return f == null ? FAULT_UNKNOWN : f;
    }

    /** Comma-separated reason list for the prompt. */
    public static String reasonList() {
        return String.join(new List<String>(REASONS), ', ');
    }

    public static String objectionList() {
        return String.join(new List<String>(OBJECTIONS), ', ');
    }
}