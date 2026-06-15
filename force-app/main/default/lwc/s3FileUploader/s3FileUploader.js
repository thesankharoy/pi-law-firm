import { LightningElement, api, track } from 'lwc';

import { wire } from 'lwc';

import getDocuments
from '@salesforce/apex/S3FileUploadController.getDocuments';

import deleteDocument
from '@salesforce/apex/S3FileUploadController.deleteDocument';

import { refreshApex }
from '@salesforce/apex';

import LightningConfirm
from 'lightning/confirm';

import uploadFileToS3
from '@salesforce/apex/S3FileUploadController.uploadFile';

import { ShowToastEvent }
from 'lightning/platformShowToastEvent';

export default class FileUploader extends LightningElement {

    @api recordId;

    @track isLoading = false;

    fileData;
    uploadedUrl;
    
    @track documents = [];

    wiredDocsResult;




    handleFileChange(event) {

        const file = event.target.files[0];

        if (!file) {
            return;
        }

        console.log('Selected File:', file);

        const reader = new FileReader();

        reader.onload = () => {

            const base64 =
                reader.result.split(',')[1];

            let contentType = file.type;

            if (!contentType) {

                const extension =
                    file.name.split('.').pop().toLowerCase();

                const mimeTypes = {

                    pdf: 'application/pdf',

                    png: 'image/png',

                    jpg: 'image/jpeg',

                    jpeg: 'image/jpeg',

                    gif: 'image/gif',

                    txt: 'text/plain',

                    csv: 'text/csv',

                    doc: 'application/msword',

                    docx:
                        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',

                    xls:
                        'application/vnd.ms-excel',

                    xlsx:
                        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                };

                contentType =
                    mimeTypes[extension] ||
                    'application/octet-stream';
            }

            this.fileData = {
                fileName: file.name,
                contentType: contentType,
                base64: base64
            };

            console.log(
                'Prepared File Data',
                JSON.stringify(this.fileData)
            );
        };

        reader.readAsDataURL(file);
    }

    uploadFile() {

        if (!this.fileData) {

            this.showToast(
                'Error',
                'Please select a file first.',
                'error'
            );

            return;
        }

        this.isLoading = true;

        console.log(
            'Uploading with Record Id:',
            this.recordId
        );

        uploadFileToS3({
            fileName: this.fileData.fileName,
            contentType: this.fileData.contentType,
            base64Data: this.fileData.base64,
            intakeId: this.recordId
        })
        .then(result => {

            this.uploadedUrl = result;

            console.log(
                'Uploaded URL:',
                result
            );

            this.showToast(
                'Success',
                'File uploaded successfully.',
                'success'
            );

            this.fileData = null;
            return refreshApex(
                this.wiredDocsResult
            );
        })
        .catch(error => {

            console.error(error);

            let message =
                error?.body?.message ||
                error?.message ||
                'Unknown error';

            this.showToast(
                'Upload Failed',
                message,
                'error'
            );
        })
        .finally(() => {

            this.isLoading = false;
        });
    }

    @wire(getDocuments, {
    intakeId: '$recordId'
                            })
    wiredDocuments(result) {

        this.wiredDocsResult = result;

        if(result.data){

            this.documents = result.data;

        } else if(result.error){

            console.error(result.error);
        }
    }

    handleView(event) {

        const url =
            event.currentTarget.dataset.url;

        window.open(
            url,
            '_blank'
        );
    }


    async handleDelete(event) {

    const documentId =
        event.currentTarget.dataset.id;

    const confirmed =
        await LightningConfirm.open({

            message:
                'Are you sure you want to delete this file?',

            variant: 'header',

            label: 'Confirm Delete'
        });

    if (!confirmed) {
        return;
    }

    this.isLoading = true;

    try {

        await deleteDocument({
            documentId
        });

        this.showToast(
            'Success',
            'File deleted successfully.',
            'success'
        );

        await refreshApex(
            this.wiredDocsResult
        );

    } catch(error) {

        let message =
            error?.body?.message ||
            error?.message ||
            'Unknown error';

        this.showToast(
            'Delete Failed',
            message,
            'error'
        );

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