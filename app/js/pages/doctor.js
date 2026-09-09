/**
 * WDOS Doctor — Phase 64.1. One press runs the whole truth: build and
 * database versions, who you are, whether messaging WOULD permit you (the
 * live policy verdict, not a guess), realtime round-trip timing, the
 * programme calendar state, the AI translation lane, and the voice Space.
 * Every row is PASS / FAIL / detail, with a Copy report button — so root
 * cause always comes from evidence, never assumption.
 */
import { readAuthLog } from '../core/db.js';
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { db, getSession, getOrgSetting, programmeState,
  EXPECTED_SCHEMA_VERSION, APP_VERSION } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast } from '../components/toast.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.doctor',
  });
  const out = shell.outlet;
  clear(out);

  const lines = [];
  const list = el('div', { class: 'card' });
  // v67.1: auth event log (last 30), newest first, copyable
  const log = readAuthLog().slice().reverse();
  const authCard = el('div', { class: 'card' }, [
    el('h3', { text: 'Auth events (this browser, newest first)' }),
    el('pre', { style: 'font-size:11px;white-space:pre-wrap;word-break:break-all;', text: log.length
      ? log.map((e) => `${e.at}  ${e.event}  ${e.hash || ''}  v${e.build || ''}${e.page ? '  page=' + e.page : ''}`).join('\n')
      : 'No auth events recorded yet.' }),
  ]);
  const runBtn = el('button', { class: 'btn btn--primary',
    text: t('doc.run') });
  const copyBtn = el('button', { class: 'btn btn--quiet', hidden: true,
    text: t('doc.copy'),
    onclick: () => {
      navigator.clipboard?.writeText(lines.join('\n'));
      toast(t('doc.copied'));
    } });
  out.append(
    el('p', { class: 'muted mb-2', text: t('doc.hint') }),
    el('div', { class: 'row mb-4', style: 'gap:8px;' }, [runBtn, copyBtn]),
    list, authCard);

  function row(status, name, detail) {
    const icon = status === 'PASS' ? '\u2705'
      : status === 'FAIL' ? '\u274C' : '\u26A0\uFE0F';
    lines.push(`${icon} ${name}: ${detail}`);
    list.append(el('div', { class: 'row',
      style: 'gap:10px;padding:8px 0;border-bottom:1px solid var(--line);'
        + 'align-items:flex-start;' }, [
      el('span', { text: icon }),
      el('div', { class: 'grow' }, [
        el('strong', { text: name }),
        el('div', { class: 'muted',
          style: 'font-size:13px;overflow-wrap:anywhere;', text: detail }),
      ]),
    ]));
  }

  runBtn.addEventListener('click', async () => {
    runBtn.disabled = true;
    clear(list); lines.length = 0;
    lines.push('WDOS DOCTOR REPORT — ' + new Date().toISOString());
    lines.push('origin: ' + location.origin);

    // 1 ▸ build + database versions
    row('PASS', t('doc.build'),
      `app v${APP_VERSION} · expects DB v${EXPECTED_SCHEMA_VERSION} · `
      + location.origin);
    try {
      const { data } = await db().from('schema_migrations')
        .select('version').order('version', { ascending: false }).limit(1);
      const v = data?.[0]?.version ?? 0;
      row(v >= EXPECTED_SCHEMA_VERSION ? 'PASS' : 'FAIL',
        t('doc.db'), `database v${v}`
        + (v < EXPECTED_SCHEMA_VERSION
          ? ` — run migrations up to ${EXPECTED_SCHEMA_VERSION}` : ''));
    } catch (e) { row('FAIL', t('doc.db'), e.message); }

    // 2 ▸ identity
    let myId = null;
    try {
      const session = await getSession();
      myId = session.user.id;
      row('PASS', t('doc.identity'),
        `${ctx.profile.first_name} ${ctx.profile.last_name} · `
        + `${session.user.email} · ${myId}`);
    } catch (e) { row('FAIL', t('doc.identity'), e.message); }

    // 3 ▸ roles + staff standing
    try {
      const { data: roles } = await db().from('role_assignments')
        .select('role').eq('profile_id', myId).is('ends_at', null);
      const staffQ = await db().from('staff')
        .select('position_title').eq('profile_id', myId)
        .eq('is_active', true).maybeSingle();
      row('PASS', t('doc.roles'),
        `roles: [${(roles || []).map((r) => r.role).join(', ') || 'none'}]`
        + ` · staff: ${staffQ.data ? staffQ.data.position_title : 'no'}`);
    } catch (e) { row('WARN', t('doc.roles'), e.message); }

    // 4 ▸ messaging verdict, computed by the live database rule
    try {
      const { data: other } = await db().from('staff')
        .select('profile_id, profiles:profiles(first_name)')
        .eq('is_active', true).neq('profile_id', myId).limit(1).maybeSingle();
      if (other) {
        const { data: verdict, error: vErr } = await db()
          .rpc('may_send_message',
            { sender: myId, recipient: other.profile_id });
        if (vErr) throw vErr;
        row(verdict ? 'PASS' : 'FAIL', t('doc.msgSend'),
          `may_send_message(you → ${other.profiles?.first_name || 'staff'})`
          + ` = ${verdict}`);
      } else row('WARN', t('doc.msgSend'), 'no other staff to test against');
    } catch (e) { row('FAIL', t('doc.msgSend'), e.message); }

    // 4b ▸ web push (device + database plumbing)
    try {
      const { pushState } = await import('../core/push.js');
      const st = await pushState();
      let plumbing = '';
      try {
        const { data } = await db().rpc('push_secret_status', {});
        if (data) {
          plumbing = ` \u00b7 fn url ${data.url_set ? 'set' : 'MISSING'}`
            + `, fn key ${data.key_set ? 'set' : 'MISSING'}`;
        }
      } catch { plumbing = ' \u00b7 migration 067 not run'; }
      row(st === 'on' ? 'PASS' : 'WARN', t('doc.push'),
        `this device: ${st}${plumbing}`);
    } catch (e) { row('WARN', t('doc.push'), e.message); }

    // 5 ▸ realtime round-trip
    try {
      const ms = await new Promise((res, rej) => {
        const t0 = Date.now();
        const ch = db().channel('doctor-' + t0);
        const timer = setTimeout(() => {
          try { db().removeChannel(ch); } catch { /* gone */ }
          rej(new Error('no echo within 8s'));
        }, 8000);
        ch.on('broadcast', { event: 'ping' }, () => {
          clearTimeout(timer);
          try { db().removeChannel(ch); } catch { /* gone */ }
          res(Date.now() - t0);
        }).subscribe((st) => {
          if (st === 'SUBSCRIBED') {
            ch.send({ type: 'broadcast', event: 'ping', payload: {} });
          }
        });
      });
      row('PASS', t('doc.realtime'), `echo in ${ms} ms`);
    } catch (e) { row('FAIL', t('doc.realtime'), e.message); }

    // 6 ▸ programme calendar
    try {
      const st = await programmeState();
      row('PASS', t('doc.programme'), `state: ${st} (open 3 Aug \u2192 17 Aug, grace 24 Aug)`);
    } catch (e) { row('WARN', t('doc.programme'), 'not installed: ' + e.message); }

    // 7 ▸ AI translation lane
    try {
      const { getAiToken } = await import('../core/db.js');
      const tok = String((await getAiToken()) || '');
      if (!tok) row('WARN', t('doc.ai'), 'no key saved in Settings');
      else {
        const { aiChat } = await import('../core/ai.js');
        const t0 = Date.now();
        const { text, model } = await aiChat([
          { role: 'system',
            content: 'Translate to Hausa. Reply with only the translation.' },
          { role: 'user', content: 'Welcome to WODDI.' },
        ], tok, { temperature: 0 });
        row('PASS', t('doc.ai'),
          `${model} in ${Date.now() - t0} ms \u2014 "${text.slice(0, 60)}"`);
      }
    } catch (e) { row('FAIL', t('doc.ai'), e.message); }

    // 8 ▸ voice Space
    try {
      let base = 'https://mms-meta-mms.hf.space';
      const sp = await getOrgSetting('tts_space').catch(() => null);
      if (sp && String(sp).trim()) {
        base = String(sp).trim();
        if (!base.startsWith('http')) base = 'https://' + base;
      }
      const { spaceSpeakTest } = await import('../core/ttsprobe.js');
      const t0 = Date.now();
      const url = await spaceSpeakTest(base, 'Sannu', 'hau', () => {});
      row(url ? 'PASS' : 'FAIL', t('doc.voice'),
        `${base} answered in ${Date.now() - t0} ms`);
    } catch (e) { row('FAIL', t('doc.voice'), e.message); }

    copyBtn.hidden = false;
    runBtn.disabled = false;
  });

  return shell.teardown;
}
