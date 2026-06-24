public without sharing class DocumentFolderService {
    public class FolderDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id parentId;
        @AuraEnabled
        public String path;
        @AuraEnabled
        public String createdDate;
        @AuraEnabled
        public String createdBy;
        @AuraEnabled
        public Boolean hasChildren;
    }

    // ── Ensure root folder exists for an Intake ────────────────────
    public static Folder__c ensureRoot(Id intakeId) {
        List<Folder__c> existing = [
            SELECT Id, Name, Path__c
            FROM Folder__c
            WHERE Intake__c = :intakeId AND Root__c = TRUE
            LIMIT 1
        ];
        if (!existing.isEmpty())
            return existing[0];

        Folder__c root = new Folder__c(Name = 'Home', Intake__c = intakeId, Root__c = true, Path__c = '/Home/');
        insert root;
        return root;
    }

    // ── List subfolders of a given folder ──────────────────────────
    public static List<FolderDTO> listFolders(Id parentFolderId) {
        List<Folder__c> fetched = [
            SELECT Id, Name, Parent_Folder__c, Path__c, CreatedDate, CreatedBy.Name
            FROM Folder__c
            WHERE Parent_Folder__c = :parentFolderId
            ORDER BY Name ASC
        ];
        if (fetched.isEmpty())
            return new List<FolderDTO>();

        Set<Id> folderIds = new Map<Id, Folder__c>(fetched).keySet();

        // Subfolders count
        Map<Id, Integer> subCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Parent_Folder__c pid, COUNT(Id) cnt
            FROM Folder__c
            WHERE Parent_Folder__c IN :folderIds
            GROUP BY Parent_Folder__c
        ])
            subCount.put((Id) ar.get('pid'), (Integer) ar.get('cnt'));

        // Files count
        Map<Id, Integer> fileCount = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Folder__c fid, COUNT(Id) cnt
            FROM Document__c
            WHERE Folder__c IN :folderIds AND Status__c != 'Deleted'
            GROUP BY Folder__c
        ])
            fileCount.put((Id) ar.get('fid'), (Integer) ar.get('cnt'));

        List<FolderDTO> result = new List<FolderDTO>();
        for (Folder__c f : fetched) {
            FolderDTO d = toDTO(f);
            Integer children =
                (subCount.containsKey(f.Id) ? subCount.get(f.Id) : 0) +
                (fileCount.containsKey(f.Id) ? fileCount.get(f.Id) : 0);
            d.hasChildren = children > 0;
            result.add(d);
        }
        return result;
    }

    // ── Create a folder ────────────────────────────────────────────
    public static FolderDTO createFolder(Id intakeId, Id parentFolderId, String name) {
        Folder__c parent = [SELECT Id, Path__c FROM Folder__c WHERE Id = :parentFolderId LIMIT 1];

        Folder__c f = new Folder__c(
            Name = name.trim(),
            Intake__c = intakeId,
            Root__c = false,
            Parent_Folder__c = parentFolderId,
            Path__c = parent.Path__c + name.trim() + '/'
        );
        insert f;

        return toDTO(
            [
                SELECT Id, Name, Parent_Folder__c, Path__c, CreatedDate, CreatedBy.Name
                FROM Folder__c
                WHERE Id = :f.Id
            ]
        );
    }

    // ── Rename a folder ────────────────────────────────────────────
    public static void renameFolder(Id folderId, String newName) {
        Folder__c f = [SELECT Id, Name, Path__c FROM Folder__c WHERE Id = :folderId LIMIT 1];

        String oldSegment = f.Name;
        f.Name = newName.trim();
        f.Path__c = f.Path__c.replace('/' + oldSegment + '/', '/' + newName.trim() + '/');

        update f;
    }

    // ── Delete folder (cascades to files via trigger or here) ──────
    public static void deleteFolder(Id folderId) {
        // Soft-delete files
        List<Document__c> files = [
            SELECT Id, S3_Key__c, Status__c
            FROM Document__c
            WHERE Folder__c = :folderId AND Status__c != 'Deleted'
        ];

        for (Document__c df : files)
            df.Status__c = 'Deleted';
        if (!files.isEmpty())
            update files;

        // Recurse into subfolders
        for (Folder__c sub : [SELECT Id FROM Folder__c WHERE Parent_Folder__c = :folderId])
            deleteFolder(sub.Id);

        delete new Folder__c(Id = folderId);

        // Async S3 cleanup for files that were just soft-deleted
        if (!files.isEmpty()) {
            List<String> keys = new List<String>();
            for (Document__c df : files)
                keys.add(df.S3_Key__c);
            deleteS3KeysAsync(JSON.serialize(keys));
        }
    }

    // ── Breadcrumb path from a folder up to root ───────────────────
    public static List<FolderDTO> breadcrumb(Id folderId) {
        List<FolderDTO> crumbs = new List<FolderDTO>();
        Id current = folderId;

        while (current != null) {
            // Use list-style query + guard — avoids both QueryException
            // (direct SObject assignment when 0 rows) and the add(0,x) on empty list bug
            List<Folder__c> rows = [
                SELECT Id, Name, Parent_Folder__c, Path__c, CreatedDate, CreatedBy.Name
                FROM Folder__c
                WHERE Id = :current
                LIMIT 1
            ];
            if (rows.isEmpty())
                break; // defensive — shouldn't happen in normal use

            crumbs.add(toDTO(rows[0])); // append (current → root order)
            current = rows[0].Parent_Folder__c;
        }

        // Built current→root; reverse to root→current for the UI
        List<FolderDTO> ordered = new List<FolderDTO>();
        for (Integer i = crumbs.size() - 1; i >= 0; i--) {
            ordered.add(crumbs[i]);
        }
        return ordered;
    }

    private static FolderDTO toDTO(Folder__c f) {
        FolderDTO d = new FolderDTO();
        d.id = f.Id;
        d.name = f.Name;
        d.parentId = f.Parent_Folder__c;
        d.path = f.Path__c;
        d.createdDate = f.CreatedDate != null ? f.CreatedDate.format('MMM d, yyyy') : '';
        d.createdBy = f.CreatedBy?.Name ?? '';
        return d;
    }

    @future(callout=true)
    private static void deleteS3KeysAsync(String keysJson) {
        List<Object> keys = (List<Object>) JSON.deserializeUntyped(keysJson);
        for (Object k : keys) {
            try {
                S3LambdaService.deleteObject((String) k);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'S3 delete failed: ' + k);
            }
        }
    }
}
