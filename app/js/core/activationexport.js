/**
 * WDOS Activation Exports — Phase 107. Regina (Head of Field & Country
 * Operations) asked for two always-available downloads on the Reports
 * page: an Excel file for working review, and a plain-language PDF that
 * explains the journey and the numbers to a non-technical reader, with
 * charts. The PDF's narrative is AI-written when an AI key is saved in
 * Settings, and falls back to a clear, deterministic summary written
 * from the same numbers when it is not, so the download always works.
 * House rule from the request: no em dashes anywhere in the PDF text.
 */
import { fmtDate } from './i18n.js';

/* Load a vendored script once (same pattern as documents.js). */
function loadVendor(src, globalName) {
  return new Promise((resolve, reject) => {
    if (window[globalName]) { resolve(window[globalName]); return; }
    const s = document.createElement('script');
    s.src = src;
    s.onload = () => resolve(window[globalName]);
    s.onerror = () => reject(new Error(`Could not load ${src}`));
    document.head.append(s);
  });
}

/* Strip em and en dashes from any text destined for the PDF. */
const noDash = (s) => String(s ?? '').replace(/\s*[\u2013\u2014]\s*/g, ', ');

/* One shared read of the numbers both files are built from. */
export function summarise(rows) {
  const by = (v) => rows.filter((x) => x.verdict === v).length;
  const everLogged = rows.filter((x) => x.last_seen).length;
  const now = Date.now();
  const week = 7 * 24 * 3600 * 1000;
  const logged7d = rows.filter((x) =>
    x.last_seen && now - new Date(x.last_seen).getTime() <= week).length;
  const concluded = by('passed') + by('failed');
  const itemsTotal = rows.reduce((a, x) => a + (x.items_required || 0), 0);
  const itemsDone = rows.reduce((a, x) => a + (x.items_done || 0), 0);
  return {
    total: rows.length,
    inProgress: by('in_progress'),
    passed: by('passed'),
    failed: by('failed'),
    notStarted: by('not_started'),
    everLogged,
    logged7d,
    neverLogged: rows.length - everLogged,
    passRate: concluded ? Math.round((by('passed') / concluded) * 100) : null,
    completionPct: itemsTotal
      ? Math.round((itemsDone / itemsTotal) * 100) : 0,
  };
}

/* Same idea for the established leaders (Country Reps, State
 * Coordinators and their deputies). They never take the 14 day journey,
 * so their story is told through account claiming and login activity. */
export function summariseLeaders(leaders) {
  const now = Date.now();
  const week = 7 * 24 * 3600 * 1000;
  const month = 30 * 24 * 3600 * 1000;
  const loggedIn = leaders.filter((x) => x.has_login).length;
  const active7d = leaders.filter((x) =>
    x.last_seen && now - new Date(x.last_seen).getTime() <= week).length;
  const active30d = leaders.filter((x) =>
    x.last_seen && now - new Date(x.last_seen).getTime() <= month).length;
  return {
    total: leaders.length,
    loggedIn,
    neverLoggedIn: leaders.length - loggedIn,
    active7d,
    active30d,
  };
}

/* ========================================================================
 * EXCEL — three sheets: Summary, Candidates, Login Activity
 * ===================================================================== */
export async function downloadActivationExcel(rows, leaders = []) {
  const XLSX = await loadVendor('/assets/vendor/xlsx.full.min.js', 'XLSX');
  const s = summarise(rows);
  const L = summariseLeaders(leaders);
  const today = new Date().toLocaleDateString('en-GB',
    { day: 'numeric', month: 'long', year: 'numeric' });

  const summaryAoa = [
    ['WODDI 14 Day Activation Report'],
    ['Generated', today],
    [],
    ['New applicants on the 14 day journey', 'Number'],
    ['People in the activation programme', s.total],
    ['Currently working through their 14 days', s.inProgress],
    ['Finished and passed', s.passed],
    ['Finished but did not complete', s.failed],
    ['Registered but not yet started', s.notStarted],
    [],
    ['Applicant login activity', 'Number'],
    ['Have successfully logged in at least once', s.everLogged],
    ['Active in the last 7 days', s.logged7d],
    ['Have never logged in', s.neverLogged],
    [],
    ['Overall task completion across applicants', s.completionPct + '%'],
  ];
  if (s.passRate !== null) {
    summaryAoa.push(['Pass rate among those who have finished',
      s.passRate + '%']);
  }
  if (leaders.length) {
    summaryAoa.push([],
      ['Established volunteer leaders', 'Number'],
      ['Leaders on record (Country Reps, State Coordinators, deputies)',
        L.total],
      ['Have claimed their account and logged in', L.loggedIn],
      ['Active in the last 7 days', L.active7d],
      ['Active in the last 30 days', L.active30d],
      ['Have never logged in', L.neverLoggedIn]);
  }

  const candidateHeader = ['Name', 'Membership No', 'Position Applied',
    'Country', 'State', 'LGA', 'Day Reached', 'Tasks Done',
    'Tasks Required', 'Status', 'Has Logged In', 'Last Seen',
    'Started', 'Deadline'];
  const statusWord = {
    in_progress: 'In progress', passed: 'Passed', failed: 'Did not complete',
    not_started: 'Not started',
  };
  const candidateRows = rows.map((x) => [
    x.name || '', x.membership_no || '', x.role_applied || '',
    x.country || '', x.state || '', x.lga || '',
    x.verdict === 'not_started' ? '' : x.day_reached,
    x.items_done, x.items_required,
    statusWord[x.verdict] || x.verdict,
    x.last_seen ? 'Yes' : 'No',
    x.last_seen ? fmtDate(x.last_seen) : 'Never',
    x.started_at ? fmtDate(x.started_at) : '',
    x.due_at ? fmtDate(x.due_at) : '',
  ]);

  const loginHeader = ['Name', 'Membership No', 'Has Logged In', 'Last Seen'];
  const loginRows = rows
    .slice()
    .sort((a, b) => (b.last_seen ? 1 : 0) - (a.last_seen ? 1 : 0))
    .map((x) => [x.name || '', x.membership_no || '',
      x.last_seen ? 'Yes' : 'No',
      x.last_seen ? fmtDate(x.last_seen) : 'Never']);

  const wb = XLSX.utils.book_new();
  const ws1 = XLSX.utils.aoa_to_sheet(summaryAoa);
  ws1['!cols'] = [{ wch: 52 }, { wch: 14 }];
  const ws2 = XLSX.utils.aoa_to_sheet([candidateHeader, ...candidateRows]);
  ws2['!cols'] = candidateHeader.map((h, i) =>
    ({ wch: i === 0 ? 26 : Math.max(12, h.length + 2) }));
  const ws3 = XLSX.utils.aoa_to_sheet([loginHeader, ...loginRows]);
  ws3['!cols'] = [{ wch: 26 }, { wch: 16 }, { wch: 14 }, { wch: 16 }];
  XLSX.utils.book_append_sheet(wb, ws1, 'Summary');
  XLSX.utils.book_append_sheet(wb, ws2, 'Candidates');
  XLSX.utils.book_append_sheet(wb, ws3, 'Login Activity');
  if (leaders.length) {
    const now = Date.now();
    const week = 7 * 24 * 3600 * 1000;
    const leaderHeader = ['Name', 'Code', 'Role', 'Country', 'State',
      'Has Logged In', 'Active Last 7 Days', 'Last Seen',
      'Modules Passed', 'Modules Total'];
    const leaderRows = leaders
      .slice()
      .sort((a, b) => (b.has_login ? 1 : 0) - (a.has_login ? 1 : 0))
      .map((x) => [x.name || '', x.membership_no || '',
        x.role_applied || '', x.country || '', x.state || '',
        x.has_login ? 'Yes' : 'No',
        x.last_seen
          && now - new Date(x.last_seen).getTime() <= week ? 'Yes' : 'No',
        x.last_seen ? fmtDate(x.last_seen) : 'Never',
        x.modules_passed ?? 0, x.modules_total ?? 0]);
    const ws4 = XLSX.utils.aoa_to_sheet([leaderHeader, ...leaderRows]);
    ws4['!cols'] = leaderHeader.map((h, i) =>
      ({ wch: i === 0 ? 26 : Math.max(12, h.length + 2) }));
    XLSX.utils.book_append_sheet(wb, ws4, 'Volunteer Leaders');
  }
  XLSX.writeFile(wb, 'WODDI-14Day-Activation-Report.xlsx');
}

/* ========================================================================
 * PDF — branded, charts, humanized narrative (AI with a solid fallback)
 * ===================================================================== */

/* The dependable narrative, written from the numbers, no AI needed. */
function fallbackNarrative(s, L) {
  const parts = [];
  parts.push(
    `This report covers ${s.total} people in the WODDI 14 Day Activation `
    + 'Journey. The journey is a two week guided programme that every new '
    + 'volunteer applicant completes so that WODDI can see their '
    + 'commitment, learning and readiness before any leadership decision '
    + 'is made.');
  parts.push(
    `Right now ${s.inProgress} people are actively working through their `
    + `14 days. ${s.passed} have finished and passed, ${s.failed} reached `
    + `the end of their window without completing, and ${s.notStarted} `
    + 'have registered but not yet begun.');
  parts.push(
    `On login activity, ${s.everLogged} of the ${s.total} have `
    + `successfully signed in at least once, and ${s.logged7d} have been `
    + `active in the last seven days. ${s.neverLogged} have never signed `
    + 'in, and these are the people most likely to need a friendly, '
    + 'personal check in from their coordinator.');
  parts.push(
    `Across everyone, ${s.completionPct} percent of all assigned tasks `
    + 'have been completed so far.'
    + (s.passRate !== null
      ? ` Among those whose journey has concluded, the pass rate is `
        + `${s.passRate} percent.`
      : ''));
  if (L && L.total) {
    parts.push(
      `Separately from the new applicants, WODDI has ${L.total} `
      + 'established volunteer leaders on record, the Country '
      + 'Representatives, State Coordinators and their deputies. These '
      + 'leaders do not take the 14 day journey, so their story is told '
      + `through their account activity. ${L.loggedIn} of them have `
      + `claimed their account and logged in, ${L.active7d} have been `
      + `active in the last seven days, and ${L.active30d} in the last `
      + `thirty days. ${L.neverLoggedIn} have never logged in at all, `
      + 'and reaching those leaders personally may matter even more '
      + 'than reaching quiet applicants, because each one carries '
      + 'responsibility for a whole country or state.');
  }
  parts.push(
    'A simple reading of these numbers: the people who log in early and '
    + 'often are the ones who finish. The most useful action this report '
    + 'points to is reaching out personally to anyone who has never '
    + 'logged in, because no reminder inside the system can reach '
    + 'someone who has not opened the door yet.');
  return parts.join('\n\n');
}

/* Try the AI layer for a warmer narrative; fall back without complaint. */
async function buildNarrative(s, L) {
  try {
    const { getAiToken } = await import('./db.js');
    const tok = String((await getAiToken()) || '');
    if (!tok) return fallbackNarrative(s, L);
    const { aiChat } = await import('./ai.js');
    const prompt =
      'Write a warm, plain language report summary for a non technical '
      + 'leader at a women\u2019s non profit. Explain what the numbers below '
      + 'say about the 14 day volunteer activation journey and about the '
      + 'established volunteer leaders, what is going well, what needs '
      + 'attention, and one clear recommended action. '
      + 'Keep it under 260 words. Do not use em dashes or en dashes '
      + 'anywhere. Do not use bullet points. Do not invent any number '
      + 'that is not given.\n\nNew applicants on the 14 day journey:\n'
      + `Total people: ${s.total}\n`
      + `In progress: ${s.inProgress}\nPassed: ${s.passed}\n`
      + `Did not complete: ${s.failed}\nNot started: ${s.notStarted}\n`
      + `Logged in at least once: ${s.everLogged}\n`
      + `Active in last 7 days: ${s.logged7d}\n`
      + `Never logged in: ${s.neverLogged}\n`
      + `Overall task completion: ${s.completionPct} percent\n`
      + (s.passRate !== null
        ? `Pass rate among finished: ${s.passRate} percent\n` : '')
      + (L && L.total
        ? '\nEstablished volunteer leaders (Country Representatives, '
          + 'State Coordinators and deputies, they do not take the 14 '
          + 'day journey):\n'
          + `Total leaders: ${L.total}\n`
          + `Have logged in: ${L.loggedIn}\n`
          + `Active in last 7 days: ${L.active7d}\n`
          + `Active in last 30 days: ${L.active30d}\n`
          + `Never logged in: ${L.neverLoggedIn}\n`
        : '');
    const { text } = await aiChat([
      { role: 'system',
        content: 'You write clear, warm, plain English reports. '
          + 'Never use em dashes.' },
      { role: 'user', content: prompt },
    ], tok, { temperature: 0.4 });
    const cleaned = noDash(text).trim();
    return cleaned.length > 80 ? cleaned : fallbackNarrative(s, L);
  } catch {
    return fallbackNarrative(s, L);
  }
}

const MAGENTA = [212, 0, 106];
const LEMON = [124, 181, 24];
const GREY = [110, 110, 110];

export async function downloadActivationPdf(rows, leaders = []) {
  const jspdfNs = await loadVendor('/assets/vendor/jspdf.umd.min.js', 'jspdf');
  const { jsPDF } = jspdfNs;
  const s = summarise(rows);
  const L = summariseLeaders(leaders);
  const narrative = await buildNarrative(s, leaders.length ? L : null);

  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  const H = doc.internal.pageSize.getHeight();
  const M = 44;
  let y = 0;

  const header = (title) => {
    doc.setFillColor(...MAGENTA);
    doc.rect(0, 0, W, 64, 'F');
    doc.setTextColor(255, 255, 255);
    doc.setFontSize(20); doc.setFont('helvetica', 'bold');
    doc.text('WODDI', M, 40);
    doc.setFontSize(11); doc.setFont('helvetica', 'normal');
    doc.text(noDash(title), W - M, 40, { align: 'right' });
    y = 92;
  };

  const footer = () => {
    doc.setFontSize(8); doc.setTextColor(...GREY);
    doc.text(noDash('The Nurturer, woddicrm.org'), M, H - 24);
    doc.text(String(doc.internal.getNumberOfPages()), W - M, H - 24,
      { align: 'right' });
  };

  const ensureRoom = (need, title) => {
    if (y + need > H - 50) { footer(); doc.addPage(); header(title); }
  };

  /* ---- Page 1: title, generated date, key numbers ------------------- */
  header('14 Day Activation Report');
  doc.setTextColor(20, 20, 20);
  doc.setFontSize(22); doc.setFont('helvetica', 'bold');
  doc.text('14 Day Activation Journey', M, y); y += 26;
  doc.setFontSize(11); doc.setFont('helvetica', 'normal');
  doc.setTextColor(...GREY);
  const today = new Date().toLocaleDateString('en-GB',
    { day: 'numeric', month: 'long', year: 'numeric' });
  doc.text(noDash(`Prepared for the Head of Field and Country Operations, `
    + `generated ${today}`), M, y);
  y += 30;

  const kpis = [
    ['In the programme', s.total],
    ['Working through it now', s.inProgress],
    ['Passed', s.passed],
    ['Did not complete', s.failed],
    ['Logged in at least once', s.everLogged],
    ['Never logged in', s.neverLogged],
  ];
  const boxW = (W - M * 2 - 20) / 3;
  kpis.forEach((k, i) => {
    const bx = M + (i % 3) * (boxW + 10);
    const by = y + Math.floor(i / 3) * 66;
    doc.setDrawColor(230, 230, 230);
    doc.setFillColor(250, 246, 248);
    doc.roundedRect(bx, by, boxW, 56, 6, 6, 'FD');
    doc.setFontSize(20); doc.setFont('helvetica', 'bold');
    doc.setTextColor(...MAGENTA);
    doc.text(String(k[1]), bx + 12, by + 26);
    doc.setFontSize(8.5); doc.setFont('helvetica', 'normal');
    doc.setTextColor(...GREY);
    doc.text(noDash(k[0]), bx + 12, by + 42);
  });
  y += 2 * 66 + 18;

  /* ---- charts: journey status + login activity ---------------------- */
  const barChart = (title, data, colors) => {
    ensureRoom(40 + data.length * 26, '14 Day Activation Report');
    doc.setFontSize(13); doc.setFont('helvetica', 'bold');
    doc.setTextColor(20, 20, 20);
    doc.text(noDash(title), M, y); y += 14;
    const maxV = Math.max(1, ...data.map((d) => d[1]));
    const chartW = W - M * 2 - 130;
    data.forEach((d, i) => {
      const by = y + i * 26;
      doc.setFontSize(9); doc.setFont('helvetica', 'normal');
      doc.setTextColor(60, 60, 60);
      doc.text(noDash(d[0]), M, by + 11);
      const bw = Math.max(2, (d[1] / maxV) * chartW);
      doc.setFillColor(...(colors[i % colors.length]));
      doc.roundedRect(M + 118, by, bw, 15, 3, 3, 'F');
      doc.setTextColor(20, 20, 20); doc.setFont('helvetica', 'bold');
      doc.text(String(d[1]), M + 124 + bw, by + 11);
    });
    y += data.length * 26 + 20;
  };

  barChart('Where everyone is on the journey', [
    ['In progress', s.inProgress],
    ['Passed', s.passed],
    ['Did not complete', s.failed],
    ['Not started', s.notStarted],
  ], [MAGENTA, LEMON, [180, 60, 60], [170, 170, 170]]);

  barChart('Login activity', [
    ['Logged in at least once', s.everLogged],
    ['Active in the last 7 days', s.logged7d],
    ['Never logged in', s.neverLogged],
  ], [LEMON, MAGENTA, [170, 170, 170]]);

  if (leaders.length) {
    barChart('Established leaders, how active they are', [
      ['Leaders on record', L.total],
      ['Have logged in', L.loggedIn],
      ['Active in the last 7 days', L.active7d],
      ['Active in the last 30 days', L.active30d],
      ['Never logged in', L.neverLoggedIn],
    ], [MAGENTA, LEMON, LEMON, LEMON, [170, 170, 170]]);
  }

  /* ---- the humanized narrative -------------------------------------- */
  ensureRoom(120, '14 Day Activation Report');
  doc.setFontSize(13); doc.setFont('helvetica', 'bold');
  doc.setTextColor(20, 20, 20);
  doc.text('What these numbers mean', M, y); y += 16;
  doc.setFontSize(10.5); doc.setFont('helvetica', 'normal');
  doc.setTextColor(45, 45, 45);
  const paras = noDash(narrative).split(/\n{2,}/);
  paras.forEach((p) => {
    const lines = doc.splitTextToSize(p.trim(), W - M * 2);
    ensureRoom(lines.length * 14 + 8, '14 Day Activation Report');
    doc.text(lines, M, y);
    y += lines.length * 14 + 8;
  });

  /* ---- everyone, name by name --------------------------------------- */
  footer(); doc.addPage(); header('Candidate List');
  doc.setFontSize(15); doc.setFont('helvetica', 'bold');
  doc.setTextColor(20, 20, 20);
  doc.text('Everyone in the programme', M, y); y += 20;

  const cols = [
    ['Name', 128], ['ID', 74], ['Position', 86], ['Where', 84],
    ['Day', 26], ['Tasks', 36], ['Status', 60], ['Last seen', 56],
  ];
  const statusWord = {
    in_progress: 'In progress', passed: 'Passed',
    failed: 'Not completed', not_started: 'Not started',
  };
  const drawTableHead = () => {
    doc.setFillColor(...MAGENTA);
    doc.rect(M, y, W - M * 2, 18, 'F');
    doc.setFontSize(8); doc.setFont('helvetica', 'bold');
    doc.setTextColor(255, 255, 255);
    let cx = M + 4;
    cols.forEach(([label, w]) => { doc.text(label, cx, y + 12); cx += w; });
    y += 22;
  };
  drawTableHead();
  doc.setFont('helvetica', 'normal'); doc.setTextColor(40, 40, 40);
  rows.forEach((x, idx) => {
    if (y > H - 60) {
      footer(); doc.addPage(); header('Candidate List'); drawTableHead();
      doc.setFont('helvetica', 'normal'); doc.setTextColor(40, 40, 40);
    }
    if (idx % 2 === 1) {
      doc.setFillColor(248, 244, 246);
      doc.rect(M, y - 9, W - M * 2, 16, 'F');
    }
    doc.setFontSize(7.5);
    const cells = [
      x.name || '', x.membership_no || '', x.role_applied || '',
      [x.country, x.state].filter(Boolean).join(', '),
      x.verdict === 'not_started' ? '' : String(x.day_reached),
      `${x.items_done}/${x.items_required}`,
      statusWord[x.verdict] || x.verdict,
      x.last_seen ? fmtDate(x.last_seen) : 'Never',
    ];
    let cx = M + 4;
    cells.forEach((c, i) => {
      const wLimit = cols[i][1] - 6;
      let txt = noDash(c);
      while (doc.getTextWidth(txt) > wLimit && txt.length > 3) {
        txt = txt.slice(0, -2);
      }
      doc.text(txt, cx, y + 3);
      cx += cols[i][1];
    });
    y += 16;
  });
  footer();

  /* ---- the established leaders, name by name ------------------------ */
  if (leaders.length) {
    doc.addPage(); header('Volunteer Leaders');
    doc.setFontSize(15); doc.setFont('helvetica', 'bold');
    doc.setTextColor(20, 20, 20);
    doc.text('Established volunteer leaders', M, y); y += 16;
    doc.setFontSize(9.5); doc.setFont('helvetica', 'normal');
    doc.setTextColor(...GREY);
    doc.text(noDash('Country Representatives, State Coordinators and their '
      + 'deputies. They do not take the 14 day journey, so this shows '
      + 'their account and login activity instead.'), M, y,
    { maxWidth: W - M * 2 }); y += 26;

    const lcols = [
      ['Name', 132], ['Code', 66], ['Role', 118], ['Where', 96],
      ['Logged in', 46], ['Last seen', 56],
    ];
    const drawLeaderHead = () => {
      doc.setFillColor(...MAGENTA);
      doc.rect(M, y, W - M * 2, 18, 'F');
      doc.setFontSize(8); doc.setFont('helvetica', 'bold');
      doc.setTextColor(255, 255, 255);
      let lx = M + 4;
      lcols.forEach(([label, w]) => { doc.text(label, lx, y + 12); lx += w; });
      y += 22;
    };
    drawLeaderHead();
    doc.setFont('helvetica', 'normal'); doc.setTextColor(40, 40, 40);
    const sorted = leaders.slice().sort((a, b) =>
      (b.has_login ? 1 : 0) - (a.has_login ? 1 : 0)
      || String(a.country || '').localeCompare(String(b.country || '')));
    sorted.forEach((x, idx) => {
      if (y > H - 60) {
        footer(); doc.addPage(); header('Volunteer Leaders');
        drawLeaderHead();
        doc.setFont('helvetica', 'normal'); doc.setTextColor(40, 40, 40);
      }
      if (idx % 2 === 1) {
        doc.setFillColor(248, 244, 246);
        doc.rect(M, y - 9, W - M * 2, 16, 'F');
      }
      doc.setFontSize(7.5);
      const cells2 = [
        x.name || '', x.membership_no || '', x.role_applied || '',
        [x.country, x.state].filter(Boolean).join(', '),
        x.has_login ? 'Yes' : 'No',
        x.last_seen ? fmtDate(x.last_seen) : 'Never',
      ];
      let lx = M + 4;
      cells2.forEach((c, i) => {
        const wLimit = lcols[i][1] - 6;
        let txt = noDash(c);
        while (doc.getTextWidth(txt) > wLimit && txt.length > 3) {
          txt = txt.slice(0, -2);
        }
        doc.text(txt, lx, y + 3);
        lx += lcols[i][1];
      });
      y += 16;
    });
    footer();
  }

  doc.save('WODDI-14Day-Activation-Report.pdf');
}
