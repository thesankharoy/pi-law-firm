import { LightningElement, wire } from 'lwc';
import getLeakageData from '@salesforce/apex/RevenueLeakageController.getLeakageData';
import getResponseTimeData from '@salesforce/apex/IntakeDashboardController.getResponseTimeData';

export default class RevenueLeakageDashboard extends LightningElement {

    leakageData = [];
    responseData = [];

    /* ===================================
       LEAKAGE DATA
    =================================== */

    @wire(getLeakageData)
    wiredData({ data, error }) {

        if (data) {

            const maxValue = Math.max(
                ...data.map(item => item.count),
                1
            );

            this.leakageData = data.map(item => {

                const width =
                    (item.count / maxValue) * 100;

                return {

                    ...item,

                    widthStyle: `width:${width}%;`,

                    dropOffPercent:
                        item.dropOffPercent != null
                            ? Number(item.dropOffPercent).toFixed(0)
                            : '',

                    stageClass:
                        `stage-bar ${this.getStageClass(item.stageName)}`,

                    dropClass:
                        item.dropOff > 0
                            ? 'drop-warning'
                            : 'drop-success'
                };
            });

        } else if (error) {

            console.error(
                'Leakage Data Error',
                error
            );
        }
    }

    /* ===================================
       RESPONSE TIME DATA
    =================================== */

@wire(getResponseTimeData)
wiredDatas({ data, error }) {
    if (data) {
        // find the slowest source's time (the scale ceiling)
        const maxTime = data.reduce(
            (max, item) => Math.max(max, item.avgResponseTime || 0),
            0
        );

        this.responseData = data.map(item => {
            const raw = item.avgResponseTime || 0;

            // longer wait -> longer bar; slowest source fills the bar
            let width = maxTime > 0 ? (raw / maxTime) * 100 : 0;
            if (width > 0 && width < 3) {
                width = 3; // keep a sliver visible for tiny non-zero values
            }

            return {
                ...item,
                avgResponseTime: this.formatTime(raw),
                widthStyle: `width:${width}%;`,
                responseClass: `response-bar ${this.getResponseClass(width)}`
            };
        });
    } else if (error) {
        console.error('Response Time Error', error);
    }
}

    /* ===================================
       STAGE COLORS
    =================================== */

  getStageClass(stageName) {

    switch (stageName) {

        case 'New':
            return 'new';

        case 'Assigned':
            return 'assigned';

        case 'Working':
            return 'working';

        case 'Under Review':
            return 'review';

        case 'Deferred':
            return 'qualified';

        case 'Spam':
            return 'working';

        case 'Retainer Agreement Sent':
            return 'sent';

        case 'Retainer Agreement Signed':
            return 'signed';

        case 'Turned Down':
            return 'working';

        case 'Referred Out':
            return 'review';

        case 'Converted':
            return 'signed';

        default:
            return 'working';
    }
}
    /* ===================================
       RESPONSE BAR COLORS
    =================================== */

getResponseClass(percentage) {
    if (percentage >= 70) return 'red';     // longest bar = slowest = problem
    if (percentage >= 40) return 'orange';  // middling
    return 'green';                          // shortest = fastest = good
}

    /* ===================================
       TIME FORMAT
    =================================== */

   formatTime(totalMinutes) {

    if (
        totalMinutes === null ||
        totalMinutes === undefined ||
        totalMinutes < 0
    ) {
        return '0s';
    }

    const totalSeconds =
        Math.round(totalMinutes * 60);

    const hours =
        Math.floor(totalSeconds / 3600);

    const minutes =
        Math.floor(
            (totalSeconds % 3600) / 60
        );

    const seconds =
        totalSeconds % 60;

    let result = '';

    if (hours > 0) {
        result += `${hours}h `;
    }

    if (minutes > 0 || hours > 0) {
        result += `${minutes}m `;
    }

    result += `${seconds}s`;

    return result.trim();
}
}