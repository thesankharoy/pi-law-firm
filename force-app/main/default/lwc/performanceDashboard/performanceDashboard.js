import { LightningElement, wire } from 'lwc';
import getPerformanceData from '@salesforce/apex/IntakeSpecialistPerformanceController.getPerformanceData';

export default class PerformanceDashboard
extends LightningElement {

    specialists = [];

    @wire(getPerformanceData)
    wiredData({ data, error }) {

        if(data){

            let rank = 1;

            this.specialists =
                data.map(item => {

                    let rankClass =
                        'rank rank-default';

                    if(rank === 1){

                        rankClass =
                            'rank rank-gold';
                    }
                    else if(rank === 2){

                        rankClass =
                            'rank rank-silver';
                    }
                    else if(rank === 3){

                        rankClass =
                            'rank rank-bronze';
                    }

                    const row = {

                        ...item,

                        rank,

                        rankClass,

                        conversionRate:
                            Number(
                                item.conversionRate
                            ).toFixed(1),

                        widthStyle:
                            `width:${item.conversionRate}%;`
                    };

                    rank++;

                    return row;
                });
        }
    }
}