import { LightningElement, wire }
from 'lwc';

import getLeakageData
from '@salesforce/apex/RetainerLeakageController.getLeakageData';

export default class RetainerLeakageDashboard
extends LightningElement {

    sentCount = 0;
    signedCount = 0;
    unsignedCount = 0;
    leakageRate = 0;

    signedPercent = 0;

    signedWidth;
    unsignedWidth;

    @wire(getLeakageData)
    wiredData({data,error}){

        if(data){

            this.sentCount =
                data.sentCount;

            this.signedCount =
                data.signedCount;

            this.unsignedCount =
                data.unsignedCount;

            this.leakageRate =
                Number(
                    data.leakageRate
                ).toFixed(1);

            this.signedPercent =
                (
                    100 -
                    data.leakageRate
                ).toFixed(1);

            this.signedWidth =
                `width:${this.signedPercent}%`;

            this.unsignedWidth =
                `width:${data.leakageRate}%`;
        }
        else if(error){

            console.error(error);
        }
    }
}