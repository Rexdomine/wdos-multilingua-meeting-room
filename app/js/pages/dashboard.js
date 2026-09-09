import { el, clear } from '../core/dom.js';
import { t, fmtNumber } from '../core/i18n.js';
import { getMyDay, getDashboardStats, getMyRoles, changePassword, getCourseStats,
  amIStaff } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { icon } from '../components/icons.js';
import { toast, toastError } from '../components/toast.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.dashboard',
  });
  const out = shell.outlet;

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }),
    el('p', { text: t('app.loading') }),
  ]));

  let day, roles = [];
  try {
    [day, roles] = await Promise.all([getMyDay(), getMyRoles()]);
  } catch (err) {
    console.error('[dashboard] view failed:', err);
    clear(out);
    out.append(errorState(() => render(root, _params, ctx), err));
    return shell.teardown;
  }

  clear(out);
  out.append(
    el('h2', { class: 'mb-4',
      text: t('day.greeting', { name: ctx.profile.first_name }) }),
    el('div', { class: 'stats' }, [
      linkTile(t('day.myTasks'), day.myOpen, '#/tasks', '', 'tasks'),
      linkTile(t('day.overdue'), day.myOverdue, '#/tasks',
        day.myOverdue > 0 ? '' : 'stat--green', 'tasks'),
      linkTile(t('day.meetingsWeek'), day.meetingsWeek, '#/meetings',
        'stat--green', 'calendar'),
      linkTile(t('day.unreadAnn'), day.annUnread, '#/announcements', '', 'megaphone'),
    ])
  );

  const isLeader = roles.length > 0;
  if (isLeader && (day.reviewQueue > 0 || day.openApps > 0)) {
    out.append(
      el('h2', { class: 'mb-4 mt-4', text: t('day.needsYou') }),
      el('div', { class: 'stats' }, [
        linkTile(t('day.tasksToReview'), day.reviewQueue, '#/tasks', '', 'check'),
        linkTile(t('day.applications'), day.openApps, '#/recruitment', '', 'userplus'),
      ])
    );
  }

  if (isLeader) {
    try {
      const s = await getDashboardStats();
      out.append(
        el('h2', { class: 'mb-4 mt-4', text: t('dash.scope') }),
        el('div', { class: 'stats' }, [
          tile(t('dash.total'), s.total, '', 'users'),
          tile(t('dash.active'), s.active, 'stat--green', 'users'),
          tile(t('dash.pipeline'), s.pipeline, '', 'userplus'),
          tile(t('dash.training'), s.training, 'stat--green', 'check'),
        ]),
        el('p', { class: 'muted', text: t('dash.scopeHint') })
      );
    } catch {
      toastError(t('errors.load'));
    }
  }

  /* --- HQ network overview (live counts from network_command + reporting) --- */
  if (ctx.hq) {
    try {
      const { db: dbc, reportingCompliance } = await import('../core/db.js');
      const [{ data: nc }, wg, wn] = await Promise.all([
        dbc().rpc('network_command', { p_net: 'all' }),
        dbc().rpc('network_command', { p_net: 'WGMN' }).then((r) => r.data).catch(() => null),
        dbc().rpc('network_command', { p_net: 'WNNN' }).then((r) => r.data).catch(() => null),
      ]);
      const tot = (nc && nc.totals) || {};
      const box = el('div', { class: 'card mt-4' });
      box.append(el('div', { class: 'card__head' }, [
        el('h3', { text: t('hqov.title') }),
        el('a', { href: '#/command', class: 'btn btn--quiet', text: t('hqov.open') })]));
      const tile = (label, value, href) => el(href ? 'a' : 'div', { class: 'vs-mini__t', href }, [
        el('b', { text: String(value ?? 0) }), el('small', { text: label })]);
      box.append(el('div', { class: 'vs-mini' }, [
        tile(t('hqov.leaders'), tot.leaders, '#/structure'),
        tile('WGMN ' + t('hqov.leadersShort'), wg?.totals?.leaders, '#/structure'),
        tile('WNNN ' + t('hqov.leadersShort'), wn?.totals?.leaders, '#/structure'),
        tile(t('hqov.countries'), `${tot.countries_covered ?? 0} / ${tot.countries_total ?? 0}`, '#/command'),
        tile(t('hqov.vacantCr'), tot.vacant_cr, '#/structure'),
        tile(t('hqov.inactive'), tot.inactive_30d, '#/command'),
      ]));
      // by level
      const lv = el('div', { class: 'row', style: 'gap:6px;flex-wrap:wrap;margin:8px 0;' });
      for (const r of (nc?.by_level || [])) lv.append(el('span', { class: 'badge badge--neutral', text: `${t(`role.${r.role}`)}: ${r.n}` }));
      if (lv.children.length) box.append(el('div', { class: 'muted', text: t('hqov.byLevel') }), lv);
      // by country (top 12 by leaders)
      const bc = (nc?.by_country || []).slice().sort((a, b) => (b.leaders || 0) - (a.leaders || 0)).slice(0, 12);
      if (bc.length) box.append(el('div', { class: 'muted', text: t('hqov.byCountry') }),
        el('div', { class: 'table-wrap' }, [el('table', { class: 'vs-table' }, [
          el('thead', {}, [el('tr', {}, [el('th', { text: t('v.country') }), el('th', { text: t('hqov.leadersShort') }),
            el('th', { text: t('hqov.members') }), el('th', { text: 'CR' }), el('th', { text: 'DCR' }), el('th', { text: t('hqov.states') })])]),
          el('tbody', {}, bc.map((c) => el('tr', {}, [el('td', { text: c.name }), el('td', { text: String(c.leaders ?? 0) }),
            el('td', { text: String(c.members ?? 0) }), el('td', { text: c.cr_filled ? '\u2713' : '\u2014' }),
            el('td', { text: c.dcr_filled ? '\u2713' : '\u2014' }), el('td', { text: `${c.states_with_coord ?? 0}/${c.states ?? 0}` })])))])]));
      // reporting + programmes
      try {
        const rc = await reportingCompliance(null, null, 'WGMN');
        const { data: ev } = await dbc().from('programme_events').select('id', { count: 'exact', head: true }).gte('event_date', new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10));
        box.append(el('div', { class: 'vs-mini', style: 'margin-top:8px;' }, [
          tile(t('hqov.reportsExpected'), rc.expected, '#/reporting/compliance'),
          tile(t('hqov.reportsSubmitted'), rc.submitted, '#/reporting/compliance'),
          tile(t('hqov.reportsApproved'), rc.approved, '#/reporting/compliance'),
          tile(t('hqov.reportsOverdue'), rc.overdue, '#/reporting/compliance'),
          tile(t('hqov.programmes30'), (ev && ev.length) || 0, '#/programmes'),
        ]));
      } catch { /* reporting module not deployed yet */ }
      out.append(box);
    } catch (e) { console.warn('[dashboard] network overview', e); }
  }

  /* --- open the mobile "My WODDI" view (volunteer leadership only) --- */
  const staffHere = await amIStaff();
  if (!staffHere && !ctx.hq) out.append(el('div', { class: 'card mt-4',
    style: 'display:flex;align-items:center;gap:12px;' }, [
    icon('home', 22),
    el('div', { style: 'flex:1;' }, [
      el('strong', { text: t('me.openTitle') }),
      el('div', { class: 'muted', style: 'font-size:13px;', text: t('me.openHint') }),
    ]),
    el('a', { href: '#/me', class: 'btn btn--primary', text: t('me.open') }),
  ]));

  /* --- learning & certification (HQ view) --- */
  try {
    const cs = await getCourseStats();
    if (cs && cs.length) {
      const card = el('div', { class: 'card mt-4' });
      card.append(el('div', { class: 'card__head' }, [
        el('h2', { text: t('course.hqTitle') }),
        el('a', { href: '#/reports', class: 'btn btn--quiet', text: t('nav.reports') }),
      ]));
      for (const c of cs) {
        card.append(el('div', { class: 'row', style: 'gap:10px;align-items:baseline;margin-bottom:6px;flex-wrap:wrap;' }, [
          el('strong', { style: 'flex:1;min-width:200px;', text: c.title }),
          el('span', { class: 'badge badge--pipeline', text: t('course.enrolledN', { n: c.enrolled }) }),
          el('span', { class: 'badge badge--active', text: t('course.certifiedN', { n: c.completed }) }),
        ]));
      }
      out.append(card);
    }
  } catch { /* HQ-only; others simply don't see it */ }

  /* --- activation journey (only while one exists) --- */
  try {
  } catch { /* journey card is optional */ }

  /* --- account security: change password (available to everyone) --- */
  const pw1 = el('input', { class: 'input', type: 'password',
    autocomplete: 'new-password' });
  const pw2 = el('input', { class: 'input', type: 'password',
    autocomplete: 'new-password' });
  const pwErr = el('p', { class: 'field__error', role: 'alert', hidden: true });
  out.append(el('div', { class: 'card mt-4' }, [
    el('div', { class: 'card__head' }, [
      el('h2', { text: t('acct.title') })]),
    el('p', { class: 'muted', text: t('acct.hint') }),
    el('div', { class: 'form-grid' }, [
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.newPw') }), pw1]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.confirmPw') }), pw2]),
    ]),
    pwErr,
    el('div', { class: 'row' }, [
      el('span', { class: 'grow' }),
      el('button', { class: 'btn btn--secondary', text: t('acct.change'),
        onclick: async (e) => {
          if (pw1.value.length < 8) {
            pwErr.textContent = t('acct.errShort');
            pwErr.hidden = false; return;
          }
          if (pw1.value !== pw2.value) {
            pwErr.textContent = t('acct.errMatch');
            pwErr.hidden = false; return;
          }
          pwErr.hidden = true;
          e.target.disabled = true;
          try {
            await changePassword(pw1.value);
            pw1.value = ''; pw2.value = '';
            toast(t('acct.changed'));
          } catch (err) {
            pwErr.textContent =
              String(err?.message ?? '').includes('different from the old')
                ? t('acct.errSame') : t('errors.save');
            pwErr.hidden = false;
          } finally { e.target.disabled = false; }
        } }),
    ]),
  ]));

  return shell.teardown;
}

function tile(label, value, extra = '', iconName = 'chart') {
  return el('div', { class: `card stat ${extra}` }, [
    el('div', { class: 'stat__icon' }, [icon(iconName, 22)]),
    el('div', { class: 'stat__body' }, [
      el('div', { class: 'stat__label', text: label }),
      el('div', { class: 'stat__value', text: fmtNumber(value) }),
    ]),
  ]);
}

function linkTile(label, value, href, extra = '', iconName = 'chart') {
  return el('a', { href, style: 'text-decoration:none;color:inherit;' },
    [tile(label, value, extra, iconName)]);
}

function errorState(retry, err) {
  return el('div', { class: 'card state' }, [
    el('h3', { text: t('errors.loadTitle') }),
    el('p', { text: t('errors.loadHint') }),
    (String(err?.message || err?.code || '') ? el('p', { class: 'muted',
      style: 'font-size:12px;word-break:break-word;',
      text: String(err?.message || err?.code || '').slice(0, 160) }) : null),
    el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: retry }),
  ]);
}
