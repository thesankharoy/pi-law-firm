public with sharing class AssignmentRuleController {
    // ── Load all rules with their conditions ─────────────────────
    @AuraEnabled(cacheable=false)
    public static List<RuleWrapper> getRules() {
        Map<String, List<ConditionWrapper>> condMap = new Map<String, List<ConditionWrapper>>();

        for (Intake_Assignment_Condition__mdt c : [
            SELECT DeveloperName, MasterLabel, Rule__r.DeveloperName, Field_API_Name__c, Operator__c, Value__c, Order__c
            FROM Intake_Assignment_Condition__mdt
            ORDER BY Order__c ASC
        ]) {
            String key = c.Rule__r.DeveloperName;
            if (!condMap.containsKey(key))
                condMap.put(key, new List<ConditionWrapper>());
            condMap.get(key).add(new ConditionWrapper(c));
        }

        List<RuleWrapper> rules = new List<RuleWrapper>();
        for (Intake_Assignment_Rule__mdt r : [
            SELECT
                DeveloperName,
                MasterLabel,
                Order__c,
                Active__c,
                Assign_To_Type__c,
                Assign_To_Id__c,
                Assign_To_Name__c,
                Condition_Logic__c,
                Stop_On_Match__c
            FROM Intake_Assignment_Rule__mdt
            ORDER BY Order__c ASC
        ]) {
            RuleWrapper w = new RuleWrapper(r);
            w.conditions = condMap.containsKey(r.DeveloperName)
                ? condMap.get(r.DeveloperName)
                : new List<ConditionWrapper>();
            rules.add(w);
        }
        return rules;
    }

    // ── Get Intake fields for condition builder dropdown ─────────
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getIntakeFields() {
        List<FieldOption> opts = new List<FieldOption>();
        Set<Schema.DisplayType> allowed = new Set<Schema.DisplayType>{
            Schema.DisplayType.PICKLIST,
            Schema.DisplayType.BOOLEAN,
            Schema.DisplayType.STRING,
            Schema.DisplayType.TEXTAREA,
            Schema.DisplayType.CURRENCY,
            Schema.DisplayType.INTEGER,
            Schema.DisplayType.DOUBLE
        };

        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Intake__c.fields.getMap();

        for (String key : fieldMap.keySet()) {
            Schema.DescribeFieldResult f = fieldMap.get(key).getDescribe();
            if (allowed.contains(f.getType()) && !f.getName().endsWith('__pc')) {
                opts.add(new FieldOption(f.getName(), f.getLabel(), String.valueOf(f.getType()), getPicklistValues(f)));
            }
        }

        opts.sort();
        return opts;
    }

    // ── Get Queues for assign-to picker ──────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> getQueues() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Group q : [
            SELECT Id, Name
            FROM Group
            WHERE Type = 'Queue'
            ORDER BY Name
        ]) {
            result.add(new Map<String, String>{ 'id' => q.Id, 'name' => q.Name });
        }
        return result;
    }

    // ── Get Users for assign-to picker ───────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getUsers() {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (User u : [SELECT Id, Name FROM User WHERE IsActive = TRUE ORDER BY Name LIMIT 500]) {
            result.add(new Map<String, String>{ 'id' => u.Id, 'name' => u.Name });
        }
        return result;
    }

    // ── Save a rule + its conditions via Metadata API ────────────
    @AuraEnabled
    public static String saveRule(String ruleJson) {
        RuleWrapper rule = (RuleWrapper) JSON.deserialize(ruleJson, RuleWrapper.class);

        Metadata.DeployContainer container = new Metadata.DeployContainer();

        // Rule record
        Metadata.CustomMetadata ruleMd = buildRuleMd(rule);
        container.addMetadata(ruleMd);

        // Condition records — delete old ones by naming convention, re-create
        Integer i = 1;
        for (ConditionWrapper cond : rule.conditions) {
            cond.developerName = rule.developerName + '_Cond_' + i;
            container.addMetadata(buildConditionMd(cond, rule.developerName));
            i++;
        }

        MetadataCallback cb = new MetadataCallback();
        Id jobId = Metadata.Operations.enqueueDeployment(container, cb);
        return jobId;
    }

    // ── Delete a rule ────────────────────────────────────────────
    @AuraEnabled
    public static void toggleRule(String developerName, Boolean isActive) {
        // We can't delete CMT via Metadata API easily — instead deactivate
        // To truly delete, use Setup UI or SFDX
        // Here we just toggle active flag
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Intake_Assignment_Rule.' + developerName;
        md.label = developerName.replace('_', ' ');
        md.values = new List<Metadata.CustomMetadataValue>{ makeField('Active__c', isActive) };

        Metadata.DeployContainer c = new Metadata.DeployContainer();
        c.addMetadata(md);
        Metadata.Operations.enqueueDeployment(c, new MetadataCallback());
    }

    // ── Reorder rules ─────────────────────────────────────────────
    @AuraEnabled
    public static void reorderRules(List<String> orderedDeveloperNames) {
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        Integer order = 1;
        for (String devName : orderedDeveloperNames) {
            Metadata.CustomMetadata md = new Metadata.CustomMetadata();
            md.fullName = 'Intake_Assignment_Rule.' + devName;
            md.label = devName;
            md.values = new List<Metadata.CustomMetadataValue>{ makeField('Order__c', order) };
            container.addMetadata(md);
            order++;
        }
        Metadata.Operations.enqueueDeployment(container, new MetadataCallback());
    }

    // ── Helpers ───────────────────────────────────────────────────
    private static Metadata.CustomMetadata buildRuleMd(RuleWrapper rule) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Intake_Assignment_Rule.' + rule.developerName;
        md.label = rule.label;
        md.values = new List<Metadata.CustomMetadataValue>{
            makeField('Order__c', rule.order),
            makeField('Active__c', rule.isActive),
            makeField('Assign_To_Type__c', rule.assignToType),
            makeField('Assign_To_Id__c', rule.assignToId),
            makeField('Assign_To_Name__c', rule.assignToName),
            makeField('Condition_Logic__c', rule.conditionLogic),
            makeField('Stop_On_Match__c', rule.stopOnMatch)
        };
        return md;
    }

    private static Metadata.CustomMetadata buildConditionMd(ConditionWrapper c, String ruleDev) {
        Metadata.CustomMetadata md = new Metadata.CustomMetadata();
        md.fullName = 'Intake_Assignment_Condition.' + c.developerName;
        md.label = c.developerName;
        md.values = new List<Metadata.CustomMetadataValue>{
            makeField('Rule__c', ruleDev),
            makeField('Order__c', c.order),
            makeField('Field_API_Name__c', c.fieldApiName),
            makeField('Operator__c', c.operator),
            makeField('Value__c', c.value)
        };
        return md;
    }

    private static Metadata.CustomMetadataValue makeField(String field, Object val) {
        Metadata.CustomMetadataValue f = new Metadata.CustomMetadataValue();
        f.field = field;
        f.value = val;
        return f;
    }

    private static List<String> getPicklistValues(Schema.DescribeFieldResult f) {
        List<String> vals = new List<String>();
        if (f.getType() == Schema.DisplayType.PICKLIST) {
            for (Schema.PicklistEntry e : f.getPicklistValues()) {
                if (e.isActive())
                    vals.add(e.getValue());
            }
        }
        return vals;
    }

    // ── Wrappers ──────────────────────────────────────────────────
    public class RuleWrapper implements Comparable {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Integer order;
        @AuraEnabled
        public Boolean isActive;
        @AuraEnabled
        public String assignToType;
        @AuraEnabled
        public String assignToId;
        @AuraEnabled
        public String assignToName;
        @AuraEnabled
        public String conditionLogic;
        @AuraEnabled
        public Boolean stopOnMatch;
        @AuraEnabled
        public List<ConditionWrapper> conditions;

        public RuleWrapper() {
        }
        public RuleWrapper(Intake_Assignment_Rule__mdt r) {
            this.developerName = r.DeveloperName;
            this.label = r.MasterLabel;
            this.order = Integer.valueOf(r.Order__c);
            this.isActive = r.Active__c;
            this.assignToType = r.Assign_To_Type__c;
            this.assignToId = r.Assign_To_Id__c;
            this.assignToName = r.Assign_To_Name__c;
            this.conditionLogic = r.Condition_Logic__c == null ? 'AND' : r.Condition_Logic__c;
            this.stopOnMatch = r.Stop_On_Match__c;
        }
        public Integer compareTo(Object o) {
            return this.order - ((RuleWrapper) o).order;
        }
    }

    public class ConditionWrapper {
        @AuraEnabled
        public String developerName;
        @AuraEnabled
        public Integer order;
        @AuraEnabled
        public String fieldApiName;
        @AuraEnabled
        public String operator;
        @AuraEnabled
        public String value;

        public ConditionWrapper() {
        }
        public ConditionWrapper(Intake_Assignment_Condition__mdt c) {
            this.developerName = c.DeveloperName;
            this.order = Integer.valueOf(c.Order__c);
            this.fieldApiName = c.Field_API_Name__c;
            this.operator = c.Operator__c;
            this.value = c.Value__c;
        }
    }

    public class FieldOption implements Comparable {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public List<String> picklistValues;

        public FieldOption(String v, String l, String t, List<String> pv) {
            this.value = v;
            this.label = l;
            this.type = t;
            this.picklistValues = pv;
        }
        public Integer compareTo(Object o) {
            return this.label.compareTo(((FieldOption) o).label);
        }
    }
}