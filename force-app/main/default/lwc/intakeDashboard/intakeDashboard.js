import { LightningElement, wire } from 'lwc';

import getTotalLeadsEntered from '@salesforce/apex/IntakeDashboardController.getTotalLeadsEntered';
import getSignedClients from '@salesforce/apex/IntakeDashboardController.getSignedClients';
import getConversionRate from '@salesforce/apex/IntakeDashboardController.getConversionRate';
export default class IntakeDashboard extends LightningElement {

    totalLeads = 0;
    signedClients = 0;
    conversionRate = 0;
    responseData = [];

    @wire(getTotalLeadsEntered)
    wiredLeads({ data, error }) {
        if (data) {
            this.totalLeads = data;
        } else if (error) {
            console.error(error);
        }
    }

    @wire(getSignedClients)
    wiredSignedClients({ data, error }) {
        if (data) {
            this.signedClients = data;
        } else if (error) {
            console.error(error);
        }
    }
    @wire(getConversionRate)
    wiredConversionRate({ data, error }) {
    if (data) {
        this.conversionRate = Number(data).toFixed(2);
    } else if (error) {
        console.error(error);
    }
}
 
}