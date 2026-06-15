import { LightningElement, track, wire } from 'lwc';
import getIntake from '@salesforce/apex/IntakeController.getIntake';

const COLUMNS = [
  { label: 'Name', fieldName: 'Name', type:'text' },
  { label: 'Case Quality', fieldName: 'Case_Quality__c', type: 'text', cellAttributes: { class: { fieldName: 'qualityClass'} }}
];

export default class IntakeDatatable extends LightningElement {
  
  columns = COLUMNS;

  @track data = [];

  @wire(getIntake)
  wiredIntake({ error, data }) {
    if (data) {
      this.data = data.map(row => {
        let qualityClass = '';
        if(row.Case_Quality__c === 'Hot')
          {
            qualityClass = 'hotClass';
          } 
        else if(row.Case_Quality__c === 'Warm')
          {
            qualityClass = 'warmClass';
          } 
        else if(row.Case_Quality__c === 'Cold')
          {
            qualityClass = 'coldClass';
          }
        return { ...row, recordUrl: '/' + row.Id, qualityClass };
      })
    }
  }   
}