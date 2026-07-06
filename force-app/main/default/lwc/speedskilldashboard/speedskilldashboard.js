import { LightningElement, wire } from 'lwc';
import getDashboard from '@salesforce/apex/SpeedSkillDashboardController.getDashboard';

/* -------------------------------------------------------------------------
   Speed-vs-Skill Conversion Diagnosis
   Data comes live from Apex (SpeedSkillDashboardController.getDashboard).
   The verdict engine, geometry, and rendering below are data-source agnostic
   and operate on whatever the wire returns.
   ------------------------------------------------------------------------- */

const C = {
    green: '#1B8A5A',
    gold: '#E0A400',
    red: '#B23B2E',
    speed: '#2C6E9B',
    skill: '#C2683B',
    brand: '#FFC629'
};

const VERDICTS = {
    SKILL: {
        title: 'Your bottleneck is skill',
        line: 'Intake quality — not speed — is where cases are slipping away.',
        accent: C.skill, tint: '#FBF0E9', quad: 'skill'
    },
    SPEED: {
        title: 'Your bottleneck is speed',
        line: 'Response speed — not skill — is where cases are slipping away.',
        accent: C.speed, tint: '#EAF1F6', quad: 'speed'
    },
    BOTH: {
        title: 'You\u2019re leaking on both fronts',
        line: 'Speed and intake quality are both costing you conversions.',
        accent: C.red, tint: '#FBECEA', quad: 'both'
    },
    HEALTHY: {
        title: 'No single bottleneck',
        line: 'Speed and quality are both healthy — conversion is working.',
        accent: C.green, tint: '#E9F5EF', quad: 'healthy'
    }
};

const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const speedScore = (m) => clamp(1 - Math.sqrt(Math.min(m, 60) / 60), 0, 1);
const outcomeColor = (c) => (c >= 28 ? C.green : c >= 15 ? C.gold : C.red);

function recoverableGap(buckets) {
    const total = buckets.reduce((s, b) => s + b.leads, 0);
    const best = Math.max(...buckets.map((b) => b.conv));
    const lost = buckets.reduce((s, b) => s + b.leads * (best - b.conv), 0);
    return total ? lost / total : 0;
}

export default class DelipatSpeedSkillDashboard extends LightningElement {
    days = 90;
    dash;
    error;

    @wire(getDashboard, { days: '$days' })
    wiredDash(value) {
        this.wiredResult = value;
        if (value.data) {
            this.dash = value.data;
            this.error = undefined;
        } else if (value.error) {
            this.error = value.error;
            this.dash = undefined;
        }
    }

    // ---- range filter (drives the wire) ----
    get rangeButtons() {
        return [30, 90, 365].map((n) => ({
            key: String(n),
            days: String(n),
            label: n === 365 ? 'Last 12 months' : `Last ${n} days`,
            cls: 'scn' + (n === this.days ? ' scn-active' : '')
        }));
    }
    handleRange(event) {
        this.days = parseInt(event.currentTarget.dataset.days, 10);
    }
    get rangeLabel() {
        return this.days === 365 ? 'last 12 months' : `last ${this.days} days`;
    }

    // ---- view states ----
    get isLoading() {
        return !this.dash && !this.error;
    }
    get errorMsg() {
        if (!this.error) return null;
        const e = this.error;
        return (e.body && e.body.message) ? e.body.message : 'Could not load dashboard data.';
    }
    get isEmpty() {
        return this.dash && (!this.dash.qaBuckets || this.dash.qaBuckets.length === 0);
    }

    // ---- the model ----
    get m() {
        const d = this.dash;
        if (!d || !d.qaBuckets || d.qaBuckets.length === 0) {
            return null;
        }
        const reps = Array.isArray(d.reps) ? d.reps : [];

        const L = 46, R = 14, T = 18, B = 42, W = 400, H = 320;
        const plotW = W - L - R, plotH = H - T - B;
        const xMid = L + 0.5 * plotW;
        const yMid = T + 0.30 * plotH;

        // headline numbers
        const total = d.qaBuckets.reduce((s, b) => s + b.leads, 0);
        const overallConv = d.qaBuckets.reduce((s, b) => s + b.leads * b.conv, 0) / total;
        const tl = reps.reduce((s, r) => s + r.leads, 0);
        const avgMins = tl ? reps.reduce((s, r) => s + r.leads * r.responseMins, 0) / tl : 0;
        const avgQa = tl ? reps.reduce((s, r) => s + r.leads * r.qaScore, 0) / tl : 0;

        // verdict
        const speedGap = d.speedBuckets && d.speedBuckets.length ? recoverableGap(d.speedBuckets) : 0;
        const skillGap = recoverableGap(d.qaBuckets);
        const Tg = 6;
        let v;
        if (speedGap < Tg && skillGap < Tg && overallConv >= 30) v = 'HEALTHY';
        else if (
            speedGap >= Tg && skillGap >= Tg &&
            Math.min(speedGap, skillGap) / Math.max(speedGap, skillGap) > 0.6
        ) v = 'BOTH';
        else v = skillGap >= speedGap ? 'SKILL' : 'SPEED';
        const vd = VERDICTS[v];

        const sg = Math.round(speedGap), kg = Math.round(skillGap);
        const worstQa = d.qaBuckets[d.qaBuckets.length - 1].conv;
        const bestQa = d.qaBuckets[0].conv;
        const sp = d.speedBuckets && d.speedBuckets.length ? d.speedBuckets : [{ conv: 0 }];
        const worstSpeed = sp[sp.length - 1].conv;
        const bestSpeed = sp[0].conv;

        let rec;
        if (v === 'SKILL') {
            rec = `Your team reaches leads fast — speed isn\u2019t the leak. Conversion tracks intake quality: your lowest-quality intakes convert at ${worstQa}% versus ${bestQa}% for your best. Coach the reps and call types scoring below 65 and tighten scripts and QA to recover roughly ${kg} points of conversion.`;
        } else if (v === 'SPEED') {
            rec = `Your intake quality is strong — skill isn\u2019t the leak. Conversion collapses as response time grows: leads answered after an hour convert at ${worstSpeed}% versus ${bestSpeed}% under five minutes, and too many wait. Add staffing, smarter routing, and automated/after-hours first response to recover roughly ${sg} points.`;
        } else if (v === 'BOTH') {
            rec = `Both levers are leaking. Slow response and weak intake quality each cost double-digit conversion, and your worst leads are both slow and low-quality. Fix first response (staffing/automation) and run intake coaching/QA in parallel — start in the bottom-left of the matrix, worth roughly ${sg + kg} points combined.`;
        } else {
            rec = 'No single bottleneck stands out — response is fast and intake quality is high across the board, and conversion reflects it. Hold the line and watch for drift by rep or channel.';
        }

        // quadrant rects
        const wash = (hex, a) => {
            const n = parseInt(hex.slice(1), 16);
            return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
        };
        const mkQuad = (key, x, y, w, h, color, label, lx, ly, anchor) => ({
            key, x, y, w, h, label, labelX: lx, labelY: ly, anchor,
            fill: wash(color, key === vd.quad ? 0.17 : 0.07),
            stroke: key === vd.quad ? color : 'none',
            strokeWidth: key === vd.quad ? 2 : 0,
            labelFill: color,
            labelWeight: key === vd.quad ? 700 : 600
        });
        const quads = [
            mkQuad('healthy', xMid, T, L + plotW - xMid, yMid - T, C.green, 'Healthy', L + plotW - 6, T + 16, 'end'),
            mkQuad('speed', L, T, xMid - L, yMid - T, C.speed, 'Speed-bound', L + 6, T + 16, 'start'),
            mkQuad('skill', xMid, yMid, L + plotW - xMid, T + plotH - yMid, C.skill, 'Skill-bound', L + plotW - 6, T + plotH - 8, 'end'),
            mkQuad('both', L, yMid, xMid - L, T + plotH - yMid, C.red, 'Both', L + 6, T + plotH - 8, 'start')
        ];

        // rep dots
        const minL = reps.length ? Math.min(...reps.map((r) => r.leads)) : 0;
        const maxL = reps.length ? Math.max(...reps.map((r) => r.leads)) : 0;
        const radius = (l) => 7 + (maxL === minL ? 0 : (l - minL) / (maxL - minL)) * 7;
        const dots = reps.map((r) => {
            const cx = L + speedScore(r.responseMins) * plotW;
            const cy = T + (1 - r.qaScore / 100) * plotH;
            const fast = r.responseMins <= 15, hi = r.qaScore >= 70;
            const fill = hi && fast ? C.green : hi ? C.speed : fast ? C.skill : C.red;
            return {
                key: r.name, cx: cx.toFixed(1), cy: cy.toFixed(1), r: radius(r.leads).toFixed(1),
                fill, tip: `${r.name} · ${Math.round(r.responseMins)} min · QA ${Math.round(r.qaScore)} · ${Math.round(r.conversion)}% signed · ${r.leads} leads`
            };
        });
        const showAvg = tl > 0;
        const avgCx = (L + speedScore(avgMins) * plotW).toFixed(1);
        const avgCy = (T + (1 - avgQa / 100) * plotH).toFixed(1);

        // bar strips
        const mkBars = (buckets) => {
            const max = Math.max(...buckets.map((b) => b.conv), 1);
            return buckets.map((b) => ({
                key: b.label, label: b.label, conv: b.conv + '%',
                leadPct: Math.round((b.leads / total) * 100) + '% of leads',
                style: `width:${Math.round((b.conv / max) * 100)}%;background:${outcomeColor(b.conv)}`
            }));
        };

        // gap compare
        const gapMax = Math.max(speedGap, skillGap, 1);
        const gaps = [
            { key: 'speed', label: 'Fix response speed', pts: `+${sg} pts`, style: `width:${Math.round((speedGap / gapMax) * 100)}%;background:${C.speed}` },
            { key: 'skill', label: 'Fix intake quality', pts: `+${kg} pts`, style: `width:${Math.round((skillGap / gapMax) * 100)}%;background:${C.skill}` }
        ];

        return {
            verdictTitle: vd.title,
            verdictLine: vd.line,
            recommendation: rec,
            bannerStyle: `background:${vd.tint};border-left:6px solid ${vd.accent}`,
            tagStyle: `color:${vd.accent}`,
            kpiLeads: total.toLocaleString('en-US'),
            kpiConv: Math.round(overallConv) + '%',
            kpiMins: Math.round(avgMins) + ' min',
            kpiQa: Math.round(avgQa),
            quads,
            reps: dots,
            xMid: xMid.toFixed(1), yMid: yMid.toFixed(1),
            plotL: L, plotR: L + plotW, plotT: T, plotB: T + plotH,
            showAvg, avgCx, avgCy,
            avgLabelX: avgCx, avgLabelY: (parseFloat(avgCy) - 16).toFixed(1),
            speedBars: d.speedBuckets && d.speedBuckets.length ? mkBars(d.speedBuckets) : [],
            qaBars: mkBars(d.qaBuckets),
            gaps
        };
    }
}