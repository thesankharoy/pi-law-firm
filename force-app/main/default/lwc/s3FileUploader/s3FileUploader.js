import { LightningElement, api, track, wire } from "lwc";
import getDocuments from "@salesforce/apex/S3FileUploadController.getDocuments";
import deleteDocument from "@salesforce/apex/S3FileUploadController.deleteDocument";
import getUploadUrl from "@salesforce/apex/S3PresignedUrlService.getUploadUrl";
import createDocument from "@salesforce/apex/S3PresignedUrlService.createDocument";
import { refreshApex } from "@salesforce/apex";
import LightningConfirm from "lightning/confirm";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class FileUploader extends LightningElement {
    @api recordId;

    @track isLoading = false;

    fileData;
    uploadedUrl;
    selectedFileName = "";

    @track documents = [];

    wiredDocsResult;

    handleFileChange(event) {
        const file = event.target.files[0];

        if (!file) {
            return;
        }

        this.fileData = file;
        this.selectedFileName = file.name;
    }

    async uploadFile() {
        if (!this.fileData) {
            this.showToast("Error", "Please select a file first.", "error");

            return;
        }

        this.isLoading = true;

        try {
            const safeFileName = this.fileData.name.replace(/[^a-zA-Z0-9._-]/g, "_");

            const response = await getUploadUrl({
                fileName: safeFileName,
                intakeId: this.recordId
            });

            const uploadData = JSON.parse(response);

            const uploadUrl = uploadData.uploadUrl;

            const s3Key = uploadData.key;

            const uploadResponse = await fetch(uploadUrl, {
                method: "PUT",
                body: this.fileData,
                headers: {
                    "Content-Type": this.fileData.type || "application/octet-stream"
                }
            });

            if (!uploadResponse.ok) {
                throw new Error("Failed to upload file to S3");
            }

            const fileUrl = await createDocument({
                fileName: this.fileData.name,
                s3Key: s3Key,
                intakeId: this.recordId
            });

            this.uploadedUrl = fileUrl;

            this.showToast("Success", "File uploaded successfully.", "success");

            this.fileData = null;

            await refreshApex(this.wiredDocsResult);
        } catch (error) {
            console.error(error);

            let message = error?.body?.message || error?.message || "Unknown error";

            this.showToast("Upload Failed", message, "error");
        } finally {
            this.isLoading = false;
        }
    }

    @wire(getDocuments, {
        intakeId: "$recordId"
    })
    wiredDocuments(result) {
        this.wiredDocsResult = result;

        if (result.data) {
            this.documents = result.data;
        } else if (result.error) {
            console.error(result.error);
        }
    }

    handleView(event) {
        const url = event.currentTarget.dataset.url;

        window.open(url, "_blank");
    }

    async handleDelete(event) {
        const documentId = event.currentTarget.dataset.id;

        const confirmed = await LightningConfirm.open({
            message: "Are you sure you want to delete this file?",

            variant: "header",

            label: "Confirm Delete"
        });

        if (!confirmed) {
            return;
        }

        this.isLoading = true;

        try {
            await deleteDocument({
                documentId
            });

            this.showToast("Success", "File deleted successfully.", "success");

            await refreshApex(this.wiredDocsResult);
        } catch (error) {
            let message = error?.body?.message || error?.message || "Unknown error";

            this.showToast("Delete Failed", message, "error");
        } finally {
            this.isLoading = false;
        }
    }

    get disableUpload() {
        return !this.fileData || this.isLoading;
    }

    get hasDocuments() {
        return this.documents && this.documents.length > 0;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
