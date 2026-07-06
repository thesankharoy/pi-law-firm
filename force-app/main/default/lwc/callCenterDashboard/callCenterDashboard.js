import { LightningElement, wire } from 'lwc';

import getDashboardData
from '@salesforce/apex/CallCenterDashboardController.getDashboardData';

export default class CallCenterDashboard extends LightningElement {

    totalAnswered = 0;
    answeredWithinSix = 0;
    serviceLevel = 0;
    avgAnswerTime = 0;
    avgCallDuration = 0;

    @wire(getDashboardData)
    wiredData({ error, data }) {

        if (data) {

            this.totalAnswered = data.totalAnswered;

            this.answeredWithinSix =
                data.answeredWithinSix;

            this.serviceLevel =
                Number(data.serviceLevel).toFixed(2);

            this.avgAnswerTime =
                Number(data.avgAnswerTime).toFixed(2);

            this.avgCallDuration =
                Number(data.avgCallDuration).toFixed(2);

        } else if (error) {

            console.error(error);

        }
    }
}