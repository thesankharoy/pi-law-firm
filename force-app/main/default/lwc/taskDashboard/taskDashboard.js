import { LightningElement, wire } from 'lwc';
import getWeeklyTasks from '@salesforce/apex/TaskDashboardController.getWeeklyTasks';

export default class TaskDashboard extends LightningElement {

    tasks = [];
    total = 0;
    completed = 0;
    pending = 0;

    @wire(getWeeklyTasks)
    wiredTasks({ data, error }) {
        if (data) {
            this.tasks = data;
            this.total = data.length;
            this.completed = data.filter(t => t.isCompleted).length;
            this.pending = this.total - this.completed;
        } else if (error) {
            console.error(error);
        }
    }

    openTaskList(event) {

        const type = event.currentTarget.dataset.type;

        let url = '/lightning/o/Task/list?filterName=ALL_Task';

        switch (type) {
            case 'total':
                url = '/lightning/o/Task/list?filterName=ALL_Task';
                break;

            case 'completed':
                url = '/lightning/o/Task/list?filterName=Completed_Tasks';
                break;

            case 'pending':
                url = '/lightning/o/Task/list?filterName=Miss_Folloup';
                break;

            default:
                url = '/lightning/o/Task/list?filterName=ALL_Task';
        }

        window.location.href = url;
    }

    handleSelect(event) {
        event.currentTarget.classList.add('pulse');
        setTimeout(() => {
            event.currentTarget.classList.remove('pulse');
        }, 400);
    }

    get progressStyle() {
        return `width:${this.completionPercentage}%`;
    }

    get completionPercentage() {
        if (!this.total) {
            return '0.0';
        }

        return ((this.completed / this.total) * 100).toFixed(1);
    }
}