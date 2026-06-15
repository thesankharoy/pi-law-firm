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
        }
    }

    openTaskList() {

        // ✅ Your provided list view URL
        const url =
            '/lightning/o/Task/list?filterName=00Bfj00000YQgG9EAL';

        // Option A: open same tab
        window.location.href = url;

    }

    handleSelect(event) {
        event.currentTarget.classList.add('pulse');
        setTimeout(() => {
            event.currentTarget.classList.remove('pulse');
        }, 400);
    }
}