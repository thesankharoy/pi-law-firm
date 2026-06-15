import { LightningElement, wire } from 'lwc';
import getFitRateBySource from '@salesforce/apex/IntakeFitRateController.getFitRateBySource';
import getConversionBySource from '@salesforce/apex/IntakeConversionController.getConversionBySource';
export default class IntakeFitRateDashboard
extends LightningElement {

    fitRateData = [];
    conversionData = [];

    @wire(getFitRateBySource)
    wiredData({ data, error }) {

        if(data){

            this.fitRateData =
                data.map(item => {

                    return {

                        ...item,

                        qualityRate:
                                Number(
                                    item.qualityRate
                                ).toFixed(1),

                            widthStyle:
                                `width:${item.qualityRate}%;`
                    };
                });
        }
        else if(error){

            console.error(error);
        }
    }
      @wire(getConversionBySource)
    wiredDatas({data,error}){

        if(data){

            this.conversionData =
                data.map(item => {

                    return {

                        ...item,

                        conversionRate:
                            Number(
                                item.conversionRate
                            ).toFixed(1),

                        widthStyle:
                            `width:${item.conversionRate}%;`
                    };
                });
        }
    }
}