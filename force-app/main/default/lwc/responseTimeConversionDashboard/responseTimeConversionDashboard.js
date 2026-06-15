import { LightningElement, wire }
from 'lwc';

import getResponseTimeVsConversion
from '@salesforce/apex/ResponseTimeConversionController.getResponseTimeVsConversion';

export default class ResponseTimeConversionDashboard
extends LightningElement {

    analysisData = [];

    @wire(getResponseTimeVsConversion)
    wiredData({ data, error }) {

        if(data){

            this.analysisData =
                data.map(item => {

                    return {

                        ...item,

                        widthStyle:
                            `width:${item.percentage}%;`
                    };
                });
        }
        else if(error){

            console.error(error);
        }
    }
}