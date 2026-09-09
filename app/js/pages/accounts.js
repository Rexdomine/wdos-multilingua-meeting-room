/**
 * Phase 131 — Accounts (HQ master control) at #/accounts.
 *
 * Every leader and member the organisation has, with their login state,
 * and the controls HQ asked for: create a login for an onboarded leader
 * who has none, open her dashboard read-only ("View as"), edit details,
 * seat or unseat her, walk her membership status, issue a new temporary
 * password, change her sign-in email, suspend or restore sign-in, delete
 * the account. The auth side runs through the admin-users Edge Function
 * (service key stays on the server); the profile/role side through
 * HQ-guarded RPCs. Temporary passwords are shown exactly once and never
 * stored by WDOS.
 */
import { el, clear, debounce } from '../core/dom.js';
import { t, fmtDate, fmtDateTime } from '../core/i18n.js';
import {
  hqAccountList, hqUpdateProfile, hqSetStatus, hqSetRole, hqEndRoles,
  hqLinkDirectory, adminUsers, listOrgUnits, uploadAvatar, avatarUrl, db,
  hqSetAppointment, onboardingOverview,
} from '../core/db.js';
import { apptBadge } from './structure.js';
import { renderShell } from '../components/layout.js';
import { openModal, closeModal } from '../components/modal.js';
import { toast, toastError } from '../components/toast.js';
import { icon } from '../components/icons.js';
import { AFRICAN_COUNTRIES, NG_STATES, countryIso, flagSrc } from '../core/geo.js';

const ROLES = ['country_rep', 'deputy_country_rep', 'state_coordinator',
  'assistant_state_coordinator', 'district_coordinator', 'assistant_district_coordinator',
  'cluster_coordinator', 'assistant_cluster_coordinator',
  'chapter_lead', 'assistant_chapter_lead',
  'volunteer', 'member', 'programme_staff', 'institute_admin', 'hq_team',
  'executive_director', 'super_admin'];
const POSITIONS = ROLES.slice(0, 10);
const APPT = ['appointed', 'acting', 'pending'];
const STATUSES = ['applicant', 'under_review', 'approved', 'activated', 'in_training',
  'active', 'inactive', 'suspended', 'resigned', 'removed', 'alumni', 'reinstated'];

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.accounts',
  });
  const out = shell.outlet;
  clear(out);

  let units = null;
  const unitsP = listOrgUnits().then((u) => { units = u; return u; }).catch(() => []);

  const search = el('input', { class: 'input', type: 'search',
    placeholder: t('acc.searchPh'), style: 'max-width:360px;' });
  const only = el('select', { class: 'select', style: 'width:auto;' }, [
    el('option', { value: '', text: t('acc.fAll') }),
    el('option', { value: 'leaders', text: t('acc.fLeaders') }),
    el('option', { value: 'nologin', text: t('acc.fNoLogin') }),
    el('option', { value: 'suspended', text: t('acc.fSuspended') }),
    el('option', { value: 'never', text: t('acc.fNever') }),
    el('option', { value: 'onboarding', text: t('acc.fOnboarding') }),
    el('option', { value: 'acceptance', text: t('acc.fAcceptance') }),
  ]);
  const addBtn = el('button', { class: 'btn btn--primary', text: t('acc.addLeader'),
    onclick: () => createModal(null) });
  const summary = el('p', { class: 'muted' });
  const listBox = el('div');
  out.append(
    el('p', { class: 'muted mb-2', text: t('acc.sub') }),
    el('div', { class: 'row mb-4', style: 'gap:10px;' }, [search, only, el('span', { class: 'grow' }), addBtn]),
    summary, listBox);

  // the admin function must be deployed for the auth-side buttons to work
  let fnOk = null;
  adminUsers('ping').then(() => { fnOk = true; })
    .catch((e) => {
      fnOk = false;
      out.insertBefore(el('div', { class: 'offline-banner',
        style: 'background:var(--warn-tint);color:var(--warn);',
        text: t('acc.fnMissing', { why: e?.code || e?.message || '' }) }), summary);
    });

  let rows = [];
  let photoBust = Date.now();
  let onb = {};
  async function load() {
    clear(listBox);
    listBox.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    try {
      const [o, r] = await Promise.all([onboardingOverview().catch(() => ({})), hqAccountList(search.value.trim(), 1000)]);
      onb = o || {}; rows = r || [];
    }
    catch (err) {
      clear(listBox);
      listBox.append(el('p', { class: 'muted', text: err?.message === 'HQ only'
        ? t('atlas.hqOnly') : (err?.message || t('errors.load')) }));
      return;
    }
    draw();
  }
  function draw() {
    clear(listBox);
    const f = only.value;
    const shown = rows.filter((r) => {
      if (f === 'leaders') return r.is_leader || (r.roles || []).length;
      if (f === 'nologin') return !r.has_login;
      if (f === 'suspended') return r.banned;
      if (f === 'never') return r.has_login && !r.last_sign_in_at;
      if (f === 'onboarding') { const o = onb[r.id]; return o && o.done < o.total; }
      if (f === 'acceptance') return (r.roles || []).some((x) => x.accepted_at === null && !x.declined_at);
      return true;
    });
    summary.textContent = t('acc.summary', {
      n: shown.length, login: rows.filter((r) => r.has_login).length,
      none: rows.filter((r) => !r.has_login).length,
      susp: rows.filter((r) => r.banned).length });
    if (!shown.length) { listBox.append(el('p', { class: 'muted', text: t('acc.none') })); return; }
    for (const r of shown) listBox.append(row(r));
  }
  search.addEventListener('input', debounce(load, 350));
  only.addEventListener('change', draw);
  await load();
  return shell.teardown;

  /* ------------------------------------------------------------ row */
  function row(r) {
    const seat = (r.roles || [])[0];
    const login = !r.has_login ? ['acc.noLogin', 'badge--exited']
      : r.banned ? ['acc.suspended', 'badge--exited']
      : !r.last_sign_in_at ? ['acc.neverIn', 'badge--paused']
      : ['acc.loginOk', 'badge--active'];
    const card = el('div', { class: 'card', style: 'margin-bottom:10px;padding:12px 14px;' });
    const initials = ((r.first_name || '?')[0] + (r.last_name || '')[0]).toUpperCase();
    const ava = r.has_login
      ? el('img', { class: 'acc-ava', alt: '', src: avatarUrl(r.id, photoBust),
          onerror: (e) => { e.target.replaceWith(el('div', { class: 'acc-ava acc-ava--none', text: initials, title: t('acc.noPhoto') })); } })
      : el('div', { class: 'acc-ava acc-ava--none', text: initials });
    const head = el('div', { class: 'row', style: 'gap:10px;align-items:flex-start;' }, [
      ava,
      el('div', { class: 'grow', style: 'min-width:220px;' }, [
        el('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;align-items:center;' }, [
          el('b', { text: r.name }),
          flagSrc(countryIso(r.country)) ? el('img', { class: 'vs-flag vs-flag--sm', src: flagSrc(countryIso(r.country)), alt: r.country || '', width: '20', height: '15', onerror: (e) => e.target.remove() }) : null,
          el('span', { class: 'badge badge--pipeline', text: r.network || '' }),
          r.status ? el('span', { class: 'badge badge--neutral', text: t(`status.${r.status}`) }) : null,
          el('span', { class: `badge ${login[1]}`, text: t(login[0]) }),
          r.is_staff ? el('span', { class: 'badge badge--neutral', text: t('acc.staff') }) : null,
        ]),
        el('div', { class: 'muted', text: [r.email, r.phone, r.membership_no].filter(Boolean).join(' \u00B7 ') }),
        el('div', { class: 'muted', style: 'display:flex;gap:6px;align-items:center;flex-wrap:wrap;' }, [
          el('span', { text: [r.network, r.country, r.state_region, r.lga,
            seat ? t(`role.${seat.role}`) : (r.role_applied || t('acc.noSeat'))].filter(Boolean).join(' | ') }),
          seat ? apptBadge(seat.appointment_status) : null,
          seat ? el('span', { text: `@ ${seat.unit}` }) : null,
          seat && seat.accepted_at === null && !seat.declined_at ? el('span', { class: 'vs-badge vs-badge--amber', text: t('acc.acceptPending') }) : null,
          seat && seat.accepted_at ? el('span', { class: 'muted', text: t('acc.acceptedOn', { d: fmtDate(seat.accepted_at) }) }) : null,
          onb[r.id] ? el('span', { class: `vs-badge vs-badge--${onb[r.id].done >= onb[r.id].total ? 'green' : 'amber'}`, text: t('acc.onboarding', { d: onb[r.id].done, n: onb[r.id].total }) }) : null,
        ]),
        el('div', { class: 'muted', text: r.has_login
          ? t('acc.signins', { last: r.last_sign_in_at ? fmtDateTime(r.last_sign_in_at) : t('acc.never'),
              seen: r.last_seen_at ? fmtDateTime(r.last_seen_at) : t('acc.never') })
          : t('acc.directoryOnly') }),
      ]),
    ]);
    const acts = el('div', { class: 'row', style: 'gap:6px;margin-top:8px;' });
    if (!r.has_login) {
      acts.append(btn(t('acc.createLogin'), 'btn--primary', () => createModal(r)));
    } else {
      acts.append(
        el('a', { href: `#/view-as/${r.id}`, class: 'btn btn--primary', text: t('acc.viewAs') }),
        btn(t('acc.photo'), 'btn--secondary', () => photoModal(r)),
        btn(t('acc.edit'), 'btn--secondary', () => editModal(r)),
        btn(t('acc.seat'), 'btn--secondary', () => seatModal(r)),
        btn(t('acc.status'), 'btn--secondary', () => statusModal(r)),
        btn(t('acc.resetPw'), 'btn--quiet', () => resetModal(r)),
        btn(t('acc.email'), 'btn--quiet', () => emailModal(r)),
        btn(r.banned ? t('acc.restore') : t('acc.suspend'), 'btn--quiet', () => banToggle(r)),
        btn(t('acc.delete'), 'btn--quiet', () => deleteModal(r)),
      );
    }
    card.append(head, acts);
    return card;
  }
  function btn(label, cls, onclick) {
    return el('button', { class: `btn ${cls}`, text: label, onclick });
  }
  // Function declaration on purpose: it is used by handlers that run after
  // render() has returned, so it must be hoisted (a const here would sit in
  // the temporal dead zone forever, which is exactly the v65.0 CONVENING bug).
  function needFn() {
    if (fnOk === false) { toastError(t('acc.fnMissingShort')); return false; }
    return true;
  }

  /* ------------------------------------------------------------ photo */
  function photoModal(r) {
    const preview = el('img', { class: 'acc-photo', alt: '', src: avatarUrl(r.id, photoBust),
      onerror: (e) => { e.target.style.display = 'none'; none.hidden = false; } });
    const none = el('p', { class: 'muted', hidden: true, text: t('acc.noPhoto') });
    const file = el('input', { type: 'file', accept: 'image/*', hidden: true });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const pick = el('button', { class: 'btn btn--primary', text: t('acc.choosePhoto'), onclick: () => file.click() });
    const remove = el('button', { class: 'btn btn--quiet', text: t('acc.removePhoto'), onclick: async () => {
      if (!confirm(t('acc.removePhotoConfirm', { name: r.name }))) return;
      remove.disabled = true;
      try {
        const { error } = await db().storage.from('avatars').remove([r.id]);
        if (error) throw error;
        photoBust = Date.now(); closeModal(); toast(t('acc.photoRemoved')); draw();
      } catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; remove.disabled = false; }
    } });
    file.addEventListener('change', async () => {
      const f = file.files && file.files[0]; if (!f) return;
      if (!/^image\//.test(f.type)) { err.textContent = t('acc.photoType'); err.hidden = false; return; }
      if (f.size > 5 * 1024 * 1024) { err.textContent = t('acc.photoSize'); err.hidden = false; return; }
      err.hidden = true; pick.disabled = true; pick.textContent = t('app.saving');
      try {
        await uploadAvatar(r.id, f);
        photoBust = Date.now(); closeModal(); toast(t('acc.photoSaved', { name: r.name })); draw();
      } catch (e) {
        err.textContent = e?.message || t('errors.save'); err.hidden = false;
        pick.disabled = false; pick.textContent = t('acc.choosePhoto');
      }
    });
    openModal(t('acc.photoFor', { name: r.name }), el('div', {}, [
      el('p', { class: 'muted', text: t('acc.photoHint') }),
      el('div', { class: 'row', style: 'gap:14px;align-items:center;' }, [preview, none]),
      file, err,
      el('div', { class: 'row', style: 'margin-top:12px;' }, [remove, el('span', { class: 'grow' }), pick]),
    ]));
  }

  /* ------------------------------------------------------------ create */
  function createModal(pre) {
    if (!needFn()) return;
    const v = (k) => (pre && pre[k]) || '';
    const first = el('input', { class: 'input', value: v('first_name') });
    const last = el('input', { class: 'input', value: v('last_name') });
    const email = el('input', { class: 'input', type: 'email', value: v('email') });
    const phone = el('input', { class: 'input', value: v('phone') });
    const network = sel(['WGMN', 'WNNN'], v('network') || 'WGMN');
    const country = sel(AFRICAN_COUNTRIES, v('country'), true);
    const state = el('input', { class: 'input', value: v('state_region'), list: 'acc-states' });
    const lga = el('input', { class: 'input', value: v('lga') });
    const roleApplied = positionSelect(v('role_applied'));
    const code = el('input', { class: 'input', value: v('membership_no'), placeholder: t('acc.codePh') });
    const isLeader = el('input', { type: 'checkbox', checked: pre ? !!pre.is_leader : true });
    const pw = el('input', { class: 'input', placeholder: t('acc.pwAuto'), autocomplete: 'off' });
    const seatRole = sel(['', ...ROLES.filter((x) => !['super_admin', 'executive_director', 'hq_team'].includes(x))], '', false,
      (x) => (x ? t(`role.${x}`) : t('acc.noSeatYet')));
    const seatUnit = unitPicker();
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', text: t('acc.createLoginGo') });
    go.addEventListener('click', async () => {
      err.hidden = true;
      if (!first.value.trim() || !last.value.trim()) { err.textContent = t('acc.needNames'); err.hidden = false; return; }
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.value.trim())) { err.textContent = t('acc.needEmail'); err.hidden = false; return; }
      if (pw.value && pw.value.length < 8) { err.textContent = t('acct.errShort'); err.hidden = false; return; }
      if (seatRole.value && !seatUnit.value()) { err.textContent = t('acc.needUnit'); err.hidden = false; return; }
      go.disabled = true;
      try {
        const res = await adminUsers('create', {
          email: email.value.trim(), password: pw.value || undefined,
          first_name: first.value.trim(), last_name: last.value.trim(),
          network: network.value, phone: phone.value.trim(),
          country: country.value, state_region: state.value.trim(), lga: lga.value.trim(),
          role_applied: roleApplied.value.trim(), is_leader: isLeader.checked,
          member_code: code.value.trim(),
        });
        const notes = [];
        if (pre && !pre.has_login && pre.membership_no) {
          try { await hqLinkDirectory(res.id, pre.membership_no); notes.push(t('acc.linkedDirectory')); }
          catch (e) { notes.push(t('acc.linkFailed', { why: e?.message || '' })); }
        }
        if (seatRole.value) {
          try { await hqSetRole(res.id, seatRole.value, seatUnit.value()); notes.push(t('acc.seated')); }
          catch (e) { notes.push(t('acc.seatFailed', { why: e?.message || '' })); }
        }
        closeModal();
        credentialsModal(`${first.value.trim()} ${last.value.trim()}`, res.email, res.temp_password, notes);
        await load();
      } catch (e) {
        err.textContent = e?.code === 'email_exists' ? t('acc.emailExists')
          : (e?.message || t('errors.save'));
        err.hidden = false; go.disabled = false;
      }
    });
    openModal(pre ? t('acc.createLoginFor', { name: pre.name }) : t('acc.addLeader'), el('div', {}, [
      el('p', { class: 'muted', text: t('acc.createHint') }),
      el('div', { class: 'form-grid' }, [
        field(t('v.firstName'), first), field(t('v.lastName'), last),
        field(t('v.email'), email), field(t('v.phone'), phone),
        field(t('v.network'), network), field(t('v.country'), country),
        field(t('v.state'), state), field(t('v.lga'), lga),
        field(t('v.roleApplied'), roleApplied), field(t('acc.code'), code),
        field(t('acc.tempPw'), pw),
        el('label', { class: 'field row', style: 'gap:8px;align-items:center;padding-top:26px;' },
          [isLeader, el('span', { text: t('acc.isLeader') })]),
      ]),
      el('h3', { class: 'mt-4', text: t('acc.seatHeading') }),
      el('div', { class: 'form-grid' }, [field(t('acc.role'), seatRole), field(t('acc.unit'), seatUnit.node)]),
      datalistStates(),
      err, el('div', { class: 'row' }, [el('span', { class: 'grow' }), go]),
    ]));
  }

  function credentialsModal(name, email, password, notes) {
    const pwBox = el('code', { style: 'font-size:20px;letter-spacing:1px;user-select:all;', text: password });
    const copy = el('button', { class: 'btn btn--secondary', text: t('acc.copy'), onclick: async () => {
      try { await navigator.clipboard.writeText(`WDOS login\n${email}\n${password}\nhttps://woddicrm.org`); toast(t('acc.copied')); }
      catch { toastError(t('errors.save')); }
    } });
    openModal(t('acc.credTitle'), el('div', {}, [
      el('p', { text: t('acc.credFor', { name }) }),
      el('div', { class: 'card', style: 'background:var(--green-tint);' }, [
        el('div', { class: 'muted', text: t('v.email') }), el('b', { text: email }),
        el('div', { class: 'muted mt-4', text: t('acc.tempPw') }), pwBox,
      ]),
      el('p', { class: 'muted', text: t('acc.credOnce') }),
      notes && notes.length ? el('ul', { class: 'vs-list' }, notes.map((n) => el('li', { text: n }))) : null,
      el('div', { class: 'row' }, [copy, el('span', { class: 'grow' }),
        el('button', { class: 'btn btn--primary', text: t('acc.done'), onclick: closeModal })]),
    ]));
  }

  /* ------------------------------------------------------------ edit */
  function editModal(r) {
    const first = el('input', { class: 'input', value: r.first_name || '' });
    const last = el('input', { class: 'input', value: r.last_name || '' });
    const phone = el('input', { class: 'input', value: r.phone || '' });
    const network = sel(['WGMN', 'WNNN'], r.network || 'WGMN');
    const country = sel(AFRICAN_COUNTRIES, r.country || '', true);
    const state = el('input', { class: 'input', value: r.state_region || '', list: 'acc-states' });
    const lga = el('input', { class: 'input', value: r.lga || '' });
    const roleApplied = positionSelect(r.role_applied);
    const code = el('input', { class: 'input', value: r.membership_no || '' });
    const isLeader = el('input', { type: 'checkbox', checked: !!r.is_leader });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', text: t('acc.save') });
    go.addEventListener('click', async () => {
      go.disabled = true;
      try {
        await hqUpdateProfile(r.id, {
          first_name: first.value.trim(), last_name: last.value.trim(),
          phone: phone.value.trim(), network: network.value, country: country.value,
          state_region: state.value.trim(), lga: lga.value.trim(),
          role_applied: roleApplied.value.trim(), is_leader: isLeader.checked,
          membership_no: code.value.trim(),
        });
        closeModal(); toast(t('acc.saved')); await load();
      } catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; go.disabled = false; }
    });
    openModal(t('acc.editFor', { name: r.name }), el('div', {}, [
      el('div', { class: 'form-grid' }, [
        field(t('v.firstName'), first), field(t('v.lastName'), last),
        field(t('v.phone'), phone), field(t('v.network'), network),
        field(t('v.country'), country), field(t('v.state'), state),
        field(t('v.lga'), lga), field(t('v.roleApplied'), roleApplied),
        field(t('acc.code'), code),
        el('label', { class: 'field row', style: 'gap:8px;align-items:center;padding-top:26px;' },
          [isLeader, el('span', { text: t('acc.isLeader') })]),
      ]),
      datalistStates(), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), go]),
    ]));
  }

  /* ------------------------------------------------------------ seat */
  function seatModal(r) {
    const seat = (r.roles || [])[0];
    const role = sel(ROLES, seat ? seat.role : 'country_rep', false, (x) => t(`role.${x}`));
    const unit = unitPicker(seat ? seat.unit_id : null);
    const appt = sel(APPT, (seat && seat.appointment_status) || 'appointed', false, (x) => t(`st.status_${x}`));
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', text: t('acc.seatGo') });
    go.addEventListener('click', async () => {
      if (!unit.value()) { err.textContent = t('acc.needUnit'); err.hidden = false; return; }
      go.disabled = true;
      try { await hqSetRole(r.id, role.value, unit.value(), appt.value); closeModal(); toast(t('acc.seated')); await load(); }
      catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; go.disabled = false; }
    });
    const end = el('button', { class: 'btn btn--quiet', text: t('acc.unseat'), onclick: async () => {
      if (!confirm(t('acc.unseatConfirm', { name: r.name }))) return;
      try { await hqEndRoles(r.id); closeModal(); toast(t('acc.unseated')); await load(); }
      catch (e) { toastError(e?.message || t('errors.save')); }
    } });
    openModal(t('acc.seatFor', { name: r.name }), el('div', {}, [
      el('p', { class: 'muted', text: seat
        ? t('acc.currentSeat', { role: t(`role.${seat.role}`), unit: seat.unit })
        : t('acc.noSeat') }),
      el('p', { class: 'muted', text: t('acc.seatHint') }),
      el('div', { class: 'form-grid' }, [field(t('acc.role'), role), field(t('acc.unit'), unit.node),
        field(t('st.appointment'), appt)]),
      err,
      el('div', { class: 'row' }, [seat ? end : null,
        seat ? el('button', { class: 'btn btn--secondary', text: t('acc.apptOnly'), onclick: async () => {
          try { await hqSetAppointment(r.id, appt.value); closeModal(); toast(t('acc.apptSaved')); await load(); }
          catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; }
        } }) : null,
        el('span', { class: 'grow' }), go]),
    ]));
  }

  /* ------------------------------------------------------------ status */
  function statusModal(r) {
    const status = sel(STATUSES, r.status || 'active', false, (x) => t(`status.${x}`));
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', text: t('acc.statusGo') });
    go.addEventListener('click', async () => {
      go.disabled = true;
      try { const res = await hqSetStatus(r.id, status.value); closeModal(); toast(t('acc.statusDone', { res })); await load(); }
      catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; go.disabled = false; }
    });
    openModal(t('acc.statusFor', { name: r.name }), el('div', {}, [
      el('p', { class: 'muted', text: t('acc.statusHint') }),
      field(t('acc.status'), status), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), go]),
    ]));
  }

  /* ------------------------------------------------------------ auth side */
  function resetModal(r) {
    if (!needFn()) return;
    const pw = el('input', { class: 'input', placeholder: t('acc.pwAuto'), autocomplete: 'off' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', text: t('acc.resetGo') });
    go.addEventListener('click', async () => {
      if (pw.value && pw.value.length < 8) { err.textContent = t('acct.errShort'); err.hidden = false; return; }
      go.disabled = true;
      try {
        const res = await adminUsers('set_password', { id: r.id, password: pw.value || undefined });
        closeModal(); credentialsModal(r.name, r.email, res.temp_password, [t('acc.resetNote')]);
      } catch (e) { err.textContent = e?.message || t('errors.save'); err.hidden = false; go.disabled = false; }
    });
    openModal(t('acc.resetFor', { name: r.name }), el('div', {}, [
      el('p', { class: 'muted', text: t('acc.resetHint') }),
      field(t('acc.tempPw'), pw), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), go]),
    ]));
  }

  function emailModal(r) {
    if (!needFn()) return;
    const email = el('input', { class: 'input', type: 'email', value: r.email || '' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', text: t('acc.emailGo') });
    go.addEventListener('click', async () => {
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.value.trim())) { err.textContent = t('acc.needEmail'); err.hidden = false; return; }
      go.disabled = true;
      try { await adminUsers('set_email', { id: r.id, email: email.value.trim() }); closeModal(); toast(t('acc.emailDone')); await load(); }
      catch (e) {
        err.textContent = e?.code === 'email_exists' ? t('acc.emailExists') : (e?.message || t('errors.save'));
        err.hidden = false; go.disabled = false;
      }
    });
    openModal(t('acc.emailFor', { name: r.name }), el('div', {}, [
      el('p', { class: 'muted', text: t('acc.emailHint') }),
      field(t('v.email'), email), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), go]),
    ]));
  }

  async function banToggle(r) {
    if (!needFn()) return;
    const on = !r.banned;
    if (!confirm(on ? t('acc.suspendConfirm', { name: r.name }) : t('acc.restoreConfirm', { name: r.name }))) return;
    try {
      await adminUsers('ban', { id: r.id, on });
      toast(on ? t('acc.suspendedDone') : t('acc.restoredDone'));
      await load();
    } catch (e) { toastError(e?.code === 'protected_account' ? t('acc.protected') : (e?.message || t('errors.save'))); }
  }

  function deleteModal(r) {
    if (!needFn()) return;
    const word = el('input', { class: 'input', placeholder: 'DELETE', autocomplete: 'off' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const go = el('button', { class: 'btn btn--primary', style: 'background:var(--danger);', text: t('acc.deleteGo') });
    go.addEventListener('click', async () => {
      if (word.value.trim() !== 'DELETE') { err.textContent = t('acc.deleteType'); err.hidden = false; return; }
      go.disabled = true;
      try { await adminUsers('delete', { id: r.id }); closeModal(); toast(t('acc.deleted')); await load(); }
      catch (e) {
        err.textContent = e?.code === 'protected_account' ? t('acc.protected')
          : t('acc.deleteFailed', { why: e?.message || '' });
        err.hidden = false; go.disabled = false;
      }
    });
    openModal(t('acc.deleteFor', { name: r.name }), el('div', {}, [
      el('p', { text: t('acc.deleteHint') }),
      el('p', { class: 'muted', text: t('acc.deleteAlt') }),
      field(t('acc.deleteWord'), word), err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), go]),
    ]));
  }

  /* ------------------------------------------------------------ pickers */
  function unitPicker(preset) {
    const input = el('input', { class: 'input', placeholder: t('acc.unitPh'), autocomplete: 'off' });
    const list = el('div', { class: 'acc-units', hidden: true });
    let chosen = preset || null;
    const wrap = el('div', { style: 'position:relative;' }, [input, list]);
    unitsP.then((u) => {
      if (chosen) { const hit = u.find((x) => x.id === chosen); if (hit) input.value = label(hit, u); }
    });
    const label = (x, all) => {
      const parent = all.find((p) => p.id === x.parent_id);
      return `${x.name} (${t(`v.lvl_${x.level}`)}${parent ? ' \u00B7 ' + parent.name : ''})`;
    };
    input.addEventListener('input', () => {
      chosen = null;
      const q = input.value.trim().toLowerCase();
      clear(list);
      if (!units || q.length < 2) { list.hidden = true; return; }
      const hits = units.filter((x) => x.name.toLowerCase().includes(q)).slice(0, 12);
      for (const x of hits) list.append(el('button', { class: 'acc-units__opt', text: label(x, units),
        onclick: () => { chosen = x.id; input.value = label(x, units); list.hidden = true; } }));
      list.hidden = hits.length === 0;
    });
    return { node: wrap, value: () => chosen };
  }
  /** Position Master List instead of a free-text title; an existing value
   *  that is not on the list is kept as one extra option so nothing is lost. */
  function positionSelect(cur) {
    const labels = POSITIONS.map((p) => t(`role.${p}`));
    const opts = [el('option', { value: '', text: t('acc.noPosition') })];
    for (const lb of labels) opts.push(el('option', { value: lb, text: lb, selected: lb === cur || null }));
    if (cur && !labels.includes(cur)) opts.push(el('option', { value: cur, text: `${cur} (${t('acc.legacyTitle')})`, selected: true }));
    return el('select', { class: 'select' }, opts);
  }
  function sel(opts, cur, blank = false, labelFn = null) {
    return el('select', { class: 'select' }, [
      blank ? el('option', { value: '', text: '\u2014' }) : null,
      ...opts.map((o) => el('option', { value: o, text: labelFn ? labelFn(o) : o,
        selected: o === cur || null })),
    ]);
  }
  function datalistStates() {
    return el('datalist', { id: 'acc-states' }, NG_STATES.map((s) => el('option', { value: s })));
  }
  function field(label, node) {
    return el('div', { class: 'field' }, [el('label', { class: 'field__label', text: label }), node]);
  }
}

// referenced for the icon set consistency check
export const __icons = icon;
export const __fmt = fmtDate;
