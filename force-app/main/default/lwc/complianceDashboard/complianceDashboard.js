import { LightningElement, wire, track } from 'lwc';
import getDashboardData
from '@salesforce/apex/ComplianceDashboardController.getDashboardData';

export default class ComplianceDashboard extends LightningElement {

    totalCalls = 0;
    flaggedCalls = 0;
    avgRiskScore = 0;

    @track riskLevelList = [];
    @track issueTypeList = [];

    @wire(getDashboardData)
    wiredData({ error, data }) {

        if(data){

            this.totalCalls = data.totalCalls;
            this.flaggedCalls = data.flaggedCalls;

            this.avgRiskScore =
                Number(data.avgRiskScore).toFixed(1);

            this.riskLevelList =
                Object.keys(data.riskLevels).map(key => {
                    return {
                        name: key,
                        count: data.riskLevels[key]
                    };
                });

            this.issueTypeList =
                Object.keys(data.issueTypes).map(key => {
                    return {
                        name: key,
                        count: data.issueTypes[key]
                    };
                });

        } else if(error){
            console.error(error);
        }
    }
}