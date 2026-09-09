/**
 * Ask WODDI — Phase 46. A free in-app assistant: no external AI service,
 * no API keys, no cost. It understands a set of intents (tasks, summaries,
 * follow-ups, journey, courses, feedback, automations) and answers from
 * the live database — instantly, privately, in the user's language.
 */
import { el, clear } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  getMyDay, listMyTasksBrief, getJourney, getMyEnrollments, listCourses,
  getAutomationInsights, getUatSummary, getCourseStats, runAutomations,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toastError } from '../components/toast.js';

const INTENTS = [
  { id: 'tasks', kw: ['task', 'tâche', 'tache', 'pending', 'overdue',
    'en retard', 'todo', 'to do', 'work'] },
  { id: 'summary', kw: ['summary', 'report', 'overview', 'everything',
    'résumé', 'resume', 'rapport', 'stats', 'statistics'] },
  { id: 'followup', kw: ['follow', 'remind', 'relance', 'chase', 'nudge'] },
  { id: 'journey', kw: ['journey', 'activation', 'parcours', 'day', 'jour'] },
  { id: 'courses', kw: ['course', 'cours', 'learn', 'certificate',
    'certificat', 'module', 'masterclass'] },
  { id: 'feedback', kw: ['feedback', 'uat', 'blocker', 'issue', 'bug',
    'register', 'test'] },
  { id: 'automations', kw: ['automation', 'cron', 'rule', 'run',
    'automatisation', 'règle'] },
  { id: 'help', kw: ['help', 'aide', 'what can', 'que peux', 'hi', 'hello',
    'bonjour', 'hey'] },
];

export async function render(root, _params, ctx) {
  // Phase 89: activation evidence — the system saw this visit.
  import('../core/db.js').then(({ logJourneyEvent }) =>
    logJourneyEvent('ask_explored'));

  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.ask',
  });
  const out = shell.outlet;
  clear(out);

  const log = el('div', { class: 'ask__log' });
  const input = el('input', { class: 'input', type: 'text',
    placeholder: t('ask.placeholder'), style: 'flex:1;' });
  const send = el('button', { class: 'btn btn--primary', text: t('ask.send') });
  const chips = el('div', { class: 'row mb-2', style: 'gap:8px;flex-wrap:wrap;' },
    ['tasks', 'summary', 'followup', 'journey', 'courses', 'help'].map((id) =>
      el('button', { class: 'btn btn--quiet', text: t(`ask.chip.${id}`),
        onclick: () => handle(t(`ask.chip.${id}`), id) })));

  out.append(
    el('p', { class: 'muted mb-2', text: t('ask.hint') }),
    chips, log,
    el('div', { class: 'row mt-2', style: 'gap:8px;' }, [input, send]));

  const ask = () => {
    const v = input.value.trim();
    if (!v) return;
    input.value = '';
    handle(v, null);
  };
  send.addEventListener('click', ask);
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') ask(); });

  bot([t('ask.welcome', { name: ctx.profile.first_name })]);
  return shell.teardown;

  /* ---------------- chat plumbing ---------------- */
  function bubble(cls, children) {
    const b = el('div', { class: 'ask__msg ' + cls }, children);
    log.append(b);
    log.scrollTop = log.scrollHeight;
    return b;
  }
  function me(text) { bubble('ask__msg--me', [el('span', { text })]); }
  function bot(lines) {
    bubble('ask__msg--bot', lines.map((l) =>
      typeof l === 'string' ? el('p', { text: l }) : l));
  }
  function botList(items) {
    return el('ul', { class: 'ask__list' }, items.map((i) =>
      el('li', { text: i })));
  }

  function detect(text) {
    const low = ' ' + text.toLowerCase() + ' ';
    for (const it of INTENTS) {
      if (it.kw.some((k) => low.includes(k))) return it.id;
    }
    return 'help';
  }

  async function handle(text, forced) {
    me(text);
    const thinking = bubble('ask__msg--bot', [el('div', { class: 'spinner',
      style: 'width:18px;height:18px;' })]);
    try {
      const intent = forced || detect(text);
      const reply = await answer(intent);
      thinking.remove();
      bot(reply);
    } catch {
      thinking.remove();
      bot([t('errors.loadHint')]);
    }
  }

  /* ---------------- answers ---------------- */
  async function answer(intent) {
    if (intent === 'tasks') return tasksAnswer();
    if (intent === 'summary') return summaryAnswer();
    if (intent === 'followup') return followupAnswer();
    if (intent === 'journey') return journeyAnswer();
    if (intent === 'courses') return coursesAnswer();
    if (intent === 'feedback') return feedbackAnswer();
    if (intent === 'automations') return automationsAnswer();
    return [t('ask.helpIntro'), botList([
      t('ask.chip.tasks'), t('ask.chip.summary'), t('ask.chip.followup'),
      t('ask.chip.journey'), t('ask.chip.courses'), t('ask.help.feedback'),
    ])];
  }

  async function tasksAnswer() {
    const rows = await listMyTasksBrief();
    if (!rows.length) return [t('ask.tasks.none')];
    const today = new Date().toISOString().slice(0, 10);
    const open = rows.filter((r) => ['not_started', 'in_progress'].includes(r.status));
    const overdue = open.filter((r) => r.due_on && r.due_on < today);
    const review = rows.filter((r) => r.status === 'awaiting_review');
    const done = rows.filter((r) => r.status === 'completed');
    const lines = [t('ask.tasks.head', {
      open: fmtNumber(open.length), overdue: fmtNumber(overdue.length),
      review: fmtNumber(review.length), done: fmtNumber(done.length) })];
    if (overdue.length) {
      lines.push(t('ask.tasks.overdueHead'));
      lines.push(botList(overdue.slice(0, 5).map((r) =>
        `${r.title} — ${t('ask.tasks.due', { d: fmtDate(r.due_on) })}`)));
    } else if (open.length) {
      lines.push(botList(open.slice(0, 5).map((r) => r.title
        + (r.due_on ? ` — ${t('ask.tasks.due', { d: fmtDate(r.due_on) })}` : ''))));
    }
    lines.push(el('a', { href: '#/tasks', text: t('ask.openTasks') }));
    return lines;
  }

  async function summaryAnswer() {
    // HQ gets the organisational picture; everyone else a personal one.
    try {
      const [ins, uat, cs] = await Promise.all([
        getAutomationInsights(), getUatSummary().catch(() => null),
        getCourseStats().catch(() => []),
      ]);
      const j = ins.journeys || {};
      const lines = [t('ask.sum.head')];
      lines.push(botList([
        t('ask.sum.apps', { n: fmtNumber(ins.apps_waiting ?? 0) }),
        t('ask.sum.vols', { n: fmtNumber(ins.volunteers?.waiting ?? 0) }),
        t('ask.sum.journeys', { a: fmtNumber(j.in_progress ?? 0),
          c: fmtNumber(j.completed ?? 0), o: fmtNumber(j.overdue ?? 0) }),
        ...(ins.quiz_avg_pct != null
          ? [t('ask.sum.quiz', { n: ins.quiz_avg_pct })] : []),
        ...cs.map((c) => t('ask.sum.course',
          { code: c.code, e: fmtNumber(c.enrolled), d: fmtNumber(c.completed) })),
        ...(uat ? [t('ask.sum.uat', { n: fmtNumber(uat.total ?? 0),
          b: fmtNumber(uat.open_blockers ?? 0) })] : []),
      ]));
      const recs = (ins.recommendations || [])
        .filter((r) => r.code !== 'all_clear');
      if (recs.length) {
        lines.push(t('ask.sum.recsHead'));
        lines.push(botList(recs.slice(0, 5).map((r) =>
          t(`auto.rec.${r.code}`, { n: fmtNumber(r.n) }))));
      }
      lines.push(el('a', { href: '#/reports', text: t('ask.openReports') }));
      return lines;
    } catch {
      // personal summary
      const [day, journey, enr, courses] = await Promise.all([
        getMyDay().catch(() => null),
        getJourney(ctx.profile.id).catch(() => null),
        getMyEnrollments().catch(() => []),
        listCourses().catch(() => []),
      ]);
      const lines = [t('ask.psum.head')];
      const items = [];
      if (day) items.push(t('ask.psum.day', {
        open: fmtNumber(day.myOpen ?? 0), over: fmtNumber(day.myOverdue ?? 0),
        meet: fmtNumber(day.meetingsWeek ?? 0) }));
      if (journey) items.push(t('ask.psum.journey',
        { s: t(`journey.${journey.status}`) }));
      for (const e of enr) {
        const c = courses.find((x) => x.id === e.course_id);
        if (c) items.push(e.completed_at
          ? t('ask.psum.courseDone', { title: c.title })
          : t('ask.psum.courseOn', { title: c.title }));
      }
      if (!items.length) items.push(t('ask.psum.quiet'));
      lines.push(botList(items));
      return lines;
    }
  }

  async function followupAnswer() {
    // Confirm, then run the automation engine (includes overdue-task nudges).
    const confirm = el('button', { class: 'btn btn--primary',
      text: t('ask.follow.confirm') });
    confirm.addEventListener('click', async () => {
      confirm.disabled = true;
      try {
        const res = await runAutomations();
        const n = res?.content?.task_followup ?? 0;
        bot([t('ask.follow.done', { n: fmtNumber(n) })]);
      } catch {
        toastError(t('errors.save'));
        bot([t('ask.follow.hqOnly')]);
      }
    });
    return [t('ask.follow.explain'), confirm];
  }

  async function journeyAnswer() {
    const j = await getJourney(ctx.profile.id).catch(() => null);
    if (!j) return [t('ask.journey.none')];
    const day = Math.min(14, Math.max(1, Math.floor(
      (Date.now() - new Date(j.started_at)) / 86400000) + 1));
    const deadline = j.extended_until ?? j.due_at;
    return [
      t('ask.journey.status', { s: t(`journey.${j.status}`) }),
      ...(j.status === 'in_progress'
        ? [t('ask.journey.day', { n: day, d: fmtDate(deadline) })] : []),
      el('a', { href: '#/me/journey', text: t('ask.openJourney') }),
    ];
  }

  async function coursesAnswer() {
    const [enr, courses] = await Promise.all([
      getMyEnrollments().catch(() => []), listCourses().catch(() => []),
    ]);
    if (!courses.length) return [t('course.none')];
    const items = courses.map((c) => {
      const e = enr.find((x) => x.course_id === c.id);
      if (!e) return t('ask.course.not', { title: c.title });
      return e.completed_at
        ? t('ask.course.done', { title: c.title, cert: e.cert_no || '' })
        : t('ask.course.on', { title: c.title });
    });
    return [t('ask.course.head'), botList(items),
      el('a', { href: '#/me/learn', text: t('ask.openLearn') })];
  }

  async function feedbackAnswer() {
    try {
      const s = await getUatSummary();
      return [t('ask.uat.head', { n: fmtNumber(s.total ?? 0),
        b: fmtNumber(s.open_blockers ?? 0) }),
        el('a', { href: '#/feedback', text: t('ask.openFeedback') })];
    } catch {
      return [t('ask.uat.tester'),
        el('a', { href: '#/feedback', text: t('ask.openFeedback') })];
    }
  }

  async function automationsAnswer() {
    return [t('ask.auto.explain'),
      el('a', { href: '#/settings', text: t('ask.openSettings') })];
  }
}
