import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import initDMS from "@salesforce/apex/DocumentController.initDMS";
import listFolders from "@salesforce/apex/DocumentController.listFolders";
import createFolder from "@salesforce/apex/DocumentController.createFolder";
import renameFolder from "@salesforce/apex/DocumentController.renameFolder";
import deleteFolder from "@salesforce/apex/DocumentController.deleteFolder";
import getBreadcrumb from "@salesforce/apex/DocumentController.getBreadcrumb";
import listFiles from "@salesforce/apex/DocumentController.listFiles";
import initiateUpload from "@salesforce/apex/DocumentController.initiateUpload";
import completeSingleUpload from "@salesforce/apex/DocumentController.completeSingleUpload";
import completeMultipartUpload from "@salesforce/apex/DocumentController.completeMultipartUpload";
// import abortUpload from "@salesforce/apex/DocumentController.abortUpload";
import getDownloadUrl from "@salesforce/apex/DocumentController.getDownloadUrl";
import getViewUrl from "@salesforce/apex/DocumentController.getViewUrl";
import renameFile from "@salesforce/apex/DocumentController.renameFile";
import deleteFile from "@salesforce/apex/DocumentController.deleteFile";
import searchFiles from "@salesforce/apex/DocumentController.searchFiles";

const CHUNK = 10 * 1024 * 1024; // 10 MB

function formatSize(bytes) {
    if (!bytes || bytes === 0) return "0 B";
    const u = ["B", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(i ? 1 : 0) + " " + u[i];
}

function extOf(name) {
    const p = name.lastIndexOf(".");
    return p > 0 ? name.substring(p + 1).toUpperCase() : "FILE";
}

let _uid = 0;
const uid = () => `u_${++_uid}`;

export default class IntakeDocumentManager extends LightningElement {
    @api recordId; // Intake Id from the record page

    @track isLoading = true;
    @track folders = [];
    @track files = [];
    @track breadcrumb = [];
    @track uploadItems = [];
    @track isDraggingOver = false;
    @track lastRefreshed = "—";

    // View
    @track viewMode = "folder"; // 'folder' | 'list'

    // Search
    @track searchQuery = "";

    // Modals
    @track showNewFolderModal = false;
    @track newFolderName = "";
    @track showRenameModal = false;
    @track renameName = "";
    @track showDeleteModal = false;
    @track deleteItemName = "";
    @track deleteItemType = "";
    @track deleteIsFolder = false;

    // Context menu
    @track showContextMenu = false;
    @track contextMenuStyle = "";
    _ctxItemId = null;
    _ctxItemType = null; // 'folder' | 'file'

    // State
    _rootFolderId = null;
    _currentFolderId = null;

    async connectedCallback() {
        if (!this.recordId) return; // guard — recordId not yet set by platform
        try {
            const init = await initDMS({ intakeId: this.recordId });
            this._rootFolderId = init.rootFolderId;
            this._currentFolderId = init.rootFolderId;
            await this.loadCurrentFolder();
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    // ── Load ────────────────────────────────────────────────────────
    async loadCurrentFolder() {
        this.isLoading = true;
        try {
            const [rawFolders, rawFiles, crumbs] = await Promise.all([
                listFolders({ parentFolderId: this._currentFolderId }),
                listFiles({ folderId: this._currentFolderId }),
                getBreadcrumb({ folderId: this._currentFolderId })
            ]);
            this.folders = rawFolders;
            this.files = rawFiles.map((f) => this.enrichFile(f));
            this.breadcrumb = crumbs.map((c, i) => ({
                ...c,
                hasChevron: i < crumbs.length - 1,
                cssClass: i < crumbs.length - 1 ? "crumb-btn" : "crumb-btn crumb-current"
            }));
            const now = new Date();
            this.lastRefreshed = now.toLocaleTimeString([], {
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit"
            });
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        } finally {
            this.isLoading = false;
        }
    }

    enrichFile(f) {
        return {
            ...f,
            ext: extOf(f.name),
            fileSizeLabel: formatSize(f.fileSize)
        };
    }

    handleRefresh() {
        if (!this._currentFolderId) return; // guard — initial load not finished yet
        this.loadCurrentFolder();
    }

    // ── View toggle ──────────────────────────────────────────────────
    setFolderView() {
        this.viewMode = "folder";
    }
    setListView() {
        this.viewMode = "list";
    }
    get isFolderView() {
        return this.viewMode === "folder";
    }
    get folderViewBtnClass() {
        return this.viewMode === "folder" ? "view-btn selected" : "view-btn";
    }
    get listViewBtnClass() {
        return this.viewMode === "list" ? "view-btn selected" : "view-btn";
    }
    get ctxIsFile() {
        return this._ctxItemType === "file";
    }

    // ── State getters ────────────────────────────────────────────────
    get hasFolders() {
        return this.folders.length > 0;
    }
    get hasFiles() {
        return this.files.length > 0;
    }
    get isEmpty() {
        return !this.hasFolders && !this.hasFiles;
    }
    get hasUploads() {
        return this.uploadItems.length > 0;
    }

    // ── Navigation ───────────────────────────────────────────────────
    handleFolderDblClick(e) {
        const id = e.currentTarget.dataset.id;
        this._currentFolderId = id;
        this.loadCurrentFolder();
    }
    handleFolderClick(e) {
        // Single click = visual selection only (no nav)
        e.stopPropagation();
    }
    handleFolderNameClick(e) {
        e.stopPropagation();
        const id = e.currentTarget.dataset.id;
        this._currentFolderId = id;
        this.loadCurrentFolder();
    }
    handleBreadcrumb(e) {
        const id = e.currentTarget.dataset.id;
        if (id === this._currentFolderId) return;
        this._currentFolderId = id;
        this.loadCurrentFolder();
    }

    // ── Search ───────────────────────────────────────────────────────
    _searchTimer = null;
    handleSearch(e) {
        this.searchQuery = e.target.value;
        clearTimeout(this._searchTimer);
        if (!this.searchQuery.trim()) {
            this.loadCurrentFolder();
            return;
        }
        this._searchTimer = setTimeout(async () => {
            this.isLoading = true;
            try {
                const results = await searchFiles({
                    intakeId: this.recordId,
                    query: this.searchQuery
                });
                this.folders = [];
                this.files = results.map((f) => this.enrichFile(f));
            } catch (e2) {
                this.toast("Search failed", this.errMsg(e2), "error");
            } finally {
                this.isLoading = false;
            }
        }, 400);
    }

    // ── Upload ───────────────────────────────────────────────────────
    handleUploadClick() {
        this.template.querySelector('[data-id="fileInput"]').click();
    }

    handleFileInputChange(e) {
        const files = [...e.target.files];
        e.target.value = "";
        if (files.length) this.uploadFiles(files);
    }

    handleDragEnter(e) {
        e.preventDefault();
        this.isDraggingOver = true;
    }
    handleDragOver(e) {
        e.preventDefault();
    }
    handleDragLeave(e) {
        if (!e.currentTarget.contains(e.relatedTarget)) this.isDraggingOver = false;
    }
    handleDrop(e) {
        e.preventDefault();
        this.isDraggingOver = false;
        const files = [...e.dataTransfer.files];
        if (files.length) this.uploadFiles(files);
    }

    async uploadFiles(fileList) {
        for (const file of fileList) {
            await this.uploadSingleFile(file);
        }
        await this.loadCurrentFolder();
    }

    async uploadSingleFile(file) {
        const id = uid();
        const item = {
            id,
            name: file.name,
            pct: 0,
            barStyle: "width:0%;",
            statusLabel: "Uploading…",
            rowClass: "up-row"
        };
        this.uploadItems = [...this.uploadItems, item];

        const updateItem = (patch) => {
            this.uploadItems = this.uploadItems.map((u) => (u.id !== id ? u : { ...u, ...patch }));
        };

        try {
            const init = await initiateUpload({
                intakeId: this.recordId,
                folderId: this._currentFolderId,
                fileName: file.name,
                fileSize: file.size,
                contentType: file.type || "application/octet-stream"
            });

            if (!init.isMultipart) {
                // ── Single-part XHR upload ──────────────────────────
                await this.xhrUpload(init.presignedUrl, file, "PUT", file.type, (pct) => {
                    updateItem({ pct, barStyle: `width:${pct}%;` });
                });
                await completeSingleUpload({ fileRecordId: init.fileRecordId });
            } else {
                // ── Multipart upload ────────────────────────────────
                const totalParts = init.totalParts;
                // Build part URL map
                const partUrlMap = {};
                (init.partUrls || []).forEach((p) => {
                    partUrlMap[p.partNumber] = p.url;
                });

                const completedParts = [];
                let totalUploaded = 0;

                // Upload parts — up to 3 in parallel
                const partIndices = Array.from({ length: totalParts }, (_, i) => i + 1);
                const PARALLEL = 3;
                for (let i = 0; i < partIndices.length; i += PARALLEL) {
                    const batch = partIndices.slice(i, i + PARALLEL);
                    const results = await Promise.all(
                        batch.map(async (partNumber) => {
                            const start = (partNumber - 1) * CHUNK;
                            const end = Math.min(start + CHUNK, file.size);
                            const blob = file.slice(start, end);
                            const etag = await this.xhrUpload(partUrlMap[partNumber], blob, "PUT", null, (partPct) => {
                                const partBytes = ((end - start) * partPct) / 100;
                                // We update progress by tracking total per-part contribution
                            });
                            totalUploaded += end - start;
                            const pct = Math.round((totalUploaded / file.size) * 100);
                            updateItem({ pct, barStyle: `width:${pct}%;` });
                            return { PartNumber: partNumber, ETag: etag };
                        })
                    );
                    completedParts.push(...results);
                }

                // Sort by part number before completing
                completedParts.sort((a, b) => a.PartNumber - b.PartNumber);
                await completeMultipartUpload({
                    fileRecordId: init.fileRecordId,
                    s3Key: init.s3Key,
                    uploadId: init.uploadId,
                    partsJson: JSON.stringify(completedParts)
                });
            }

            updateItem({ pct: 100, barStyle: "width:100%;", statusLabel: "Done ✓", rowClass: "up-row up-done" });
            setTimeout(() => {
                this.uploadItems = this.uploadItems.filter((u) => u.id !== id);
            }, 2500);
        } catch (e) {
            updateItem({ statusLabel: "Failed ✗", rowClass: "up-row up-error" });
            this.toast("Upload failed", `${file.name}: ${this.errMsg(e)}`, "error");
        }
    }

    /**
     * XHR PUT to S3 pre-signed URL.
     * Returns the ETag header (needed for multipart complete).
     * onProgress(pct) fires with 0-100.
     */
    xhrUpload(url, body, method, contentType, onProgress) {
        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.open(method || "PUT", url, true);
            if (contentType) xhr.setRequestHeader("Content-Type", contentType);
            xhr.upload.onprogress = (e) => {
                if (e.lengthComputable) onProgress(Math.round((e.loaded / e.total) * 100));
            };
            xhr.onload = () => {
                if (xhr.status >= 200 && xhr.status < 300) {
                    resolve(xhr.getResponseHeader("ETag") || "");
                } else {
                    reject(new Error(`S3 upload failed: HTTP ${xhr.status}`));
                }
            };
            xhr.onerror = () => reject(new Error("Network error during upload"));
            xhr.send(body);
        });
    }

    // ── File download ─────────────────────────────────────────────
    async handleFileClick(e) {
        // Single click in folder view — do nothing (open on context menu)
    }

    // Double-click on file card in folder view → view inline
    async handleFileDblClick(e) {
        e.stopPropagation();
        const id = e.currentTarget.dataset.id;
        await this.viewFile(id);
    }

    async handleFileNameClick(e) {
        e.stopPropagation();
        const id = e.currentTarget.dataset.id;
        await this.viewFile(id);
    }

    async viewFile(fileRecordId) {
        try {
            const url = await getViewUrl({ fileRecordId });
            window.open(url, "_blank", "noopener");
        } catch (e) {
            this.toast("View failed", this.errMsg(e), "error");
        }
    }

    async downloadFile(fileRecordId) {
        try {
            const url = await getDownloadUrl({ fileRecordId });
            const a = document.createElement("a");
            a.href = url;
            a.target = "_blank";
            a.rel = "noopener";
            a.click();
        } catch (e) {
            this.toast("Download failed", this.errMsg(e), "error");
        }
    }

    // ── New folder ────────────────────────────────────────────────
    handleNewFolder() {
        this.showNewFolderModal = true;
        this.newFolderName = "";
    }
    closeNewFolderModal() {
        this.showNewFolderModal = false;
    }
    handleNewFolderInput(e) {
        this.newFolderName = e.target.value;
    }
    handleNewFolderKey(e) {
        if (e.key === "Enter") this.confirmNewFolder();
    }
    get newFolderNameEmpty() {
        return !this.newFolderName?.trim();
    }

    async confirmNewFolder() {
        if (this.newFolderNameEmpty) return;
        this.showNewFolderModal = false;
        try {
            await createFolder({
                intakeId: this.recordId,
                parentFolderId: this._currentFolderId,
                name: this.newFolderName.trim()
            });
            await this.loadCurrentFolder();
            this.toast("Folder created", this.newFolderName, "success");
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        }
    }

    // ── Context menu ──────────────────────────────────────────────
    handleItemMenuClick(e) {
        e.stopPropagation();
        this._ctxItemId = e.currentTarget.dataset.id;
        this._ctxItemType = e.currentTarget.dataset.type;
        const rect = e.currentTarget.getBoundingClientRect();
        const host = this.template.querySelector(".dms-root").getBoundingClientRect();
        this.contextMenuStyle = `top:${rect.bottom - host.top + 2}px;left:${rect.left - host.left}px;`;
        this.showContextMenu = true;
    }
    handleContextMenuClose() {
        this.showContextMenu = false;
    }

    async handleContextAction(e) {
        const action = e.currentTarget.dataset.action;
        this.showContextMenu = false;
        const id = this._ctxItemId;
        const type = this._ctxItemType;

        if (action === "download" && type === "file") {
            await this.downloadFile(id);
        } else if (action === "rename") {
            const item =
                type === "folder" ? this.folders.find((f) => f.id === id) : this.files.find((f) => f.id === id);
            this.renameName = item?.name || "";
            this.showRenameModal = true;
        } else if (action === "delete") {
            const item =
                type === "folder" ? this.folders.find((f) => f.id === id) : this.files.find((f) => f.id === id);
            this.deleteItemName = item?.name || id;
            this.deleteItemType = type;
            this.deleteIsFolder = type === "folder";
            this.showDeleteModal = true;
        }
    }

    // ── Rename modal ──────────────────────────────────────────────
    closeRenameModal() {
        this.showRenameModal = false;
    }
    handleRenameInput(e) {
        this.renameName = e.target.value;
    }
    handleRenameKey(e) {
        if (e.key === "Enter") this.confirmRename();
    }
    get renameNameEmpty() {
        return !this.renameName?.trim();
    }

    async confirmRename() {
        if (this.renameNameEmpty) return;
        this.showRenameModal = false;
        try {
            if (this._ctxItemType === "folder") {
                await renameFolder({ folderId: this._ctxItemId, newName: this.renameName });
            } else {
                await renameFile({ fileRecordId: this._ctxItemId, newName: this.renameName });
            }
            await this.loadCurrentFolder();
            this.toast("Renamed", this.renameName, "success");
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        }
    }

    // ── Delete modal ──────────────────────────────────────────────
    closeDeleteModal() {
        this.showDeleteModal = false;
    }

    async confirmDelete() {
        this.showDeleteModal = false;
        try {
            if (this._ctxItemType === "folder") {
                await deleteFolder({ folderId: this._ctxItemId });
            } else {
                await deleteFile({ fileRecordId: this._ctxItemId });
            }
            await this.loadCurrentFolder();
            this.toast("Deleted", this.deleteItemName, "success");
        } catch (e) {
            this.toast("Error", this.errMsg(e), "error");
        }
    }

    handleSelectAll() {
        /* selection state — extend if needed */
    }
    stopProp(e) {
        e.stopPropagation();
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    errMsg(e) {
        return e?.body?.message || e?.message || "Unknown error";
    }
}