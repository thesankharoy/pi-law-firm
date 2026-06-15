import { LightningElement, wire }
from 'lwc';

import getCoverageData
from '@salesforce/apex/IntakeCoverageController.getCoverageData';

export default class IntakeCoverageDashboard
extends LightningElement {

    afterHoursCount = 0;
    coveredCount = 0;
    missedCount = 0;
    coverageRate = 0;

    coveredStyle;
    missedStyle;

    missedPercent = 0;

    @wire(getCoverageData)
    wiredData({data,error}){

        if(data){

            this.afterHoursCount =
                data.afterHoursCount;

            this.coveredCount =
                data.coveredCount;

            this.missedCount =
                data.missedCount;

            this.coverageRate =
                Number(
                    data.coverageRate
                ).toFixed(1);

            this.missedPercent =
                (
                    100 -
                    data.coverageRate
                ).toFixed(1);

            this.coveredStyle =
                `width:${data.coverageRate}%`;

            this.missedStyle =
                `width:${100-data.coverageRate}%`;
        }
        else if(error){

            console.error(error);
        }
    }
}