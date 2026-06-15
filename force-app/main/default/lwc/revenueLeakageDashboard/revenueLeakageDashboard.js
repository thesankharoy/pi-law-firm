import { LightningElement, wire } from 'lwc';
import getLeakageData from '@salesforce/apex/RevenueLeakageController.getLeakageData';
import getResponseTimeData
from '@salesforce/apex/IntakeDashboardController.getResponseTimeData';

export default class RevenueLeakageDashboard extends LightningElement {

    leakageData = [];
    responseData = [];

    @wire(getLeakageData)
    wiredData({ data, error }) {

        if (data) {

            const maxValue = Math.max(
                ...data.map(item => item.count)
            );

            this.leakageData = data.map(item => {

                const width =
                    (item.count / maxValue) * 100;

                return {
                    ...item,
                    widthStyle: `width:${Math.max(width,25)}%;`,
                    dropOffPercent:
                        Number(item.dropOffPercent).toFixed(1)
                };
            });

        } else if (error) {
            console.error(error);
        }
    }
      @wire(getResponseTimeData)
    wiredDatas({ data, error }) {

        if(data){

            this.responseData =
                data.map(item => {

                    return {

                        ...item,
                        avgResponseTime: this.formatTime(item.avgResponseTime),
                        widthStyle:
                            `width:${item.percentage}%;`
                    };
                });
        }
        else if(error){

            console.error(error);
        }
    }
    formatTime(totalMinutes) {

    const totalSeconds = Math.round(totalMinutes * 60);

    const hours = Math.floor(totalSeconds / 3600);

    const minutes = Math.floor(
        (totalSeconds % 3600) / 60
    );

    const seconds = totalSeconds % 60;

    let result = '';

    if (hours > 0) {
        result += `${hours}h `;
    }

    if (minutes > 0 || hours > 0) {
        result += `${minutes}m `;
    }

    result += `${seconds}s`;

    return result;
}
}