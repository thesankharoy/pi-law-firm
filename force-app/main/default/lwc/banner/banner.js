import { LightningElement, wire, api } from 'lwc';
//import CASE_QUALITY_FIELD from '@salesforce/schema/Intake__c.Case_Quality__c';
import {getRecord} from 'lightning/uiRecordApi';
import CASE_QUALITY_FIELD from '@salesforce/schema/Intake__c.Case_Quality_Derived__c';

export default class Banner extends LightningElement {
  @api recordId;

  caseQuality;

  @wire(getRecord, { recordId: '$recordId', fields: [CASE_QUALITY_FIELD] })
intakeRecord({ error, data }) {
    if (data) {
        this.caseQuality = data.fields.Case_Quality_Derived__c.value;
    } else if (error) {
        this.caseQuality = undefined;
    }
}


  get bannerClass(){
    if(this.caseQuality === 'Hot')
    {
      return 'banner hot';
    }
    else if(this.caseQuality === 'Cold')
    {
      return 'banner cold';
    }
    else if(this.caseQuality === 'Warm')
    {
      return 'banner warm';
    }
    return 'banner';
  }
}