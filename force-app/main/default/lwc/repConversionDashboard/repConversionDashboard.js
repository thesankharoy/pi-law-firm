import { LightningElement, wire } from 'lwc';

import getRepConversionData from '@salesforce/apex/RepConversionDashboardController.getRepConversionData';

export default class RepConversionDashboard
extends LightningElement {

    repData = [];

    @wire(getRepConversionData)
    wiredData({ data, error }) {

        if(data){

            this.repData =
                data.map((rep,index) => {

                    let performanceLabel;
                    let badgeClass;
                    let barClass;

                    if(rep.conversionRate >= 75){

                        performanceLabel =
                            'Excellent';

                        badgeClass =
                            'badge green';

                        barClass =
                            'progress-bar green-bar';
                    }
                    else if(rep.conversionRate >= 50){

                        performanceLabel =
                            'Good';

                        badgeClass =
                            'badge blue';

                        barClass =
                            'progress-bar blue-bar';
                    }
                    else if(rep.conversionRate >= 30){

                        performanceLabel =
                            'Average';

                        badgeClass =
                            'badge orange';

                        barClass =
                            'progress-bar orange-bar';
                    }
                    else{

                        performanceLabel =
                            'Needs Coaching';

                        badgeClass =
                            'badge red';

                        barClass =
                            'progress-bar red-bar';
                    }

                    return {

                        ...rep,

                        conversionRate:
                            Number(
                                rep.conversionRate
                            ).toFixed(1),

                        rankIcon:
                            index === 0
                            ? '🥇'
                            : index === 1
                            ? '🥈'
                            : index === 2
                            ? '🥉'
                            : '🏅',

                        badgeClass,

                        performanceLabel,

                        barClass,

                        widthStyle:
                            `width:${rep.conversionRate}%`
                    };
                });
        }
        else if(error){

            console.error(error);
        }
    }
}