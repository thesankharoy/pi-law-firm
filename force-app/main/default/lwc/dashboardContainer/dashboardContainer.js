import { LightningElement, track, wire } from 'lwc';
import getOwners from '@salesforce/apex/DashboardController.getOwners';

export default class DashboardContainer extends LightningElement {

    @track selectedTab = 'overview';
    @track selectedOwner = 'all';

    ownerOptions = [];

    @wire(getOwners)
    wiredOwners({ error, data }) {
        if (data) {
            this.ownerOptions = data;
        } else if (error) {
            console.error('Error loading owners:', error);
        }
    }

    handleOwner(event) {
        this.selectedOwner = event.detail.value;
    }

    changeTab(event) {
        this.selectedTab = event.currentTarget.dataset.tab;
    }

    // Tab CSS Classes
    get overviewClass() {
        return this.selectedTab === 'overview'
            ? 'tab active'
            : 'tab';
    }

    get teamClass() {
        return this.selectedTab === 'team'
            ? 'tab active'
            : 'tab';
    }

    get retainerClass() {
        return this.selectedTab === 'retainer'
            ? 'tab active'
            : 'tab';
    }

    get taskClass() {
        return this.selectedTab === 'tasks'
            ? 'tab active'
            : 'tab';
    }

    get auditClass() {
        return this.selectedTab === 'audit'
            ? 'tab active'
            : 'tab';
    }

    get executiveClass() {
        return this.selectedTab === 'executive'
            ? 'tab active'
            : 'tab';
    }

      get aIClass() {
        return this.selectedTab === 'ai'
            ? 'tab active'
            : 'tab';
    }

    // Conditional Rendering Getters
    get isOverview() {
        return this.selectedTab === 'overview';
    }

    get isTeam() {
        return this.selectedTab === 'team';
    }

    get isRetainer() {
        return this.selectedTab === 'retainer';
    }

    get isTasks() {
        return this.selectedTab === 'tasks';
    }

    get isAudit() {
        return this.selectedTab === 'audit';
    }

    get isExecutive() {
        return this.selectedTab === 'executive';
    }
     get isAI() {
        return this.selectedTab === 'ai';
    }
}