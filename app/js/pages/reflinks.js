/**
 * Phase 136 — Referral links.
 *   HQ (#/reflinks): create campaign links for any network / country / unit /
 *   position; every link with owner and counts; everyone who came through any
 *   link with who referred them, where they came from, location and status.
 *   Leader (mode 'mine', rendered inside the volunteer dashboard): a link per
 *   VACANT seat under her (position, location, network), a general membership
 *   link, and the people who came through her links.
 */
import { el, clear } from '../core/dom.js';
import { t, fmtDate, fmtDateTime } from '../core/i18n.js';
import { referralLinkEnsure, referralOverview, referralLinkToggle, referralUrl, structureExplorer, listOrgUnits, POSITIONS } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';
import { icon } from '../components/icons.js';

export async function render(root, _params, ctx) {
  const shell = renderShell(root, { profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.reflinks' });
  clear(shell.outlet);
  shell.outlet.append(el('h2', { class: 'rp-title', text: t('nav.reflinks') }));
  await renderReferralPanel(shell.outlet, { hq: true, profile: ctx.profile });
  return shell.teardown;
}

export async function renderReferralPanel(out, { hq, profile, net }) {
  const scope = hq ? 'hq' : 'mine';
  const box = el('div');
  out.append(box);
  await draw();

  async function draw() {
    clear(box);
    box.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    let d;
    try { d = await referralOverview(scope); }
    catch (err) { clear(box); box.append(el('p', { class: 'muted', text: err?.message || t('errors.load') })); return; }
    clear(box);
    box.append(el('p', { class: 'muted', text: hq ? t('ref.hqHint') : t('ref.mineHint') }));

    // ---- HQ: create a campaign link
    if (hq) box.append(await creator());

    // ---- Leader: vacant seats under me → a link each
    if (!hq) box.append(await vacancyLinks());

    // ---- my/all links
    const links = d.links || [];
    const lc = el('section', { class: 'card' }, [el('h3', { text: hq ? t('ref.allLinks') : t('ref.myLinks') }),
      el('p', { class: 'muted', text: t('ref.visits30', { n: d.visits_30d || 0 }) })]);
    if (!links.length) lc.append(el('p', { class: 'muted', text: t('ref.noLinks') }));
    for (const l of links) lc.append(linkRow(l));
    box.append(lc);

    // ---- people who came
    const people = d.people || [];
    const pc = el('section', { class: 'card' }, [el('h3', { text: t('ref.people', { n: people.length }) })]);
    if (!people.length) pc.append(el('p', { class: 'muted', text: t('ref.noPeople') }));
    else pc.append(el('div', { class: 'table-wrap' }, [el('table', { class: 'vs-table' }, [
      el('thead', {}, [el('tr', {}, [el('th', { text: t('ref.thPerson') }), el('th', { text: t('v.network') }),
        el('th', { text: t('ref.thLocation') }), el('th', { text: t('st.position') }), el('th', { text: t('v.thStatus') }),
        el('th', { text: t('ref.thReferredBy') }), el('th', { text: t('ref.thCameFrom') }), el('th', { text: t('ref.thWhen') })])]),
      el('tbody', {}, people.map((p) => el('tr', {}, [
        el('td', {}, [el('b', { text: p.name }), el('div', { class: 'muted', text: p.email || '' })]),
        el('td', { text: p.network || '' }), el('td', { text: p.location || '\u2014' }),
        el('td', { text: p.position || (p.kind === 'member' ? t('ref.member') : '') }),
        el('td', {}, [el('span', { class: 'vs-badge vs-badge--blue', text: p.status || '' })]),
        el('td', { text: p.referred_by || '' }), el('td', { text: p.came_from || t('ref.direct') }),
        el('td', { text: fmtDate(p.at) })])))])]));
    box.append(pc);
  }

  function linkRow(l) {
    const url = referralUrl(l.code);
    const target = [l.network, l.unit, l.role ? t(`role.${l.role}`) : t('ref.member')].filter(Boolean).join(' \u00B7 ');
    return el('div', { class: 'rp-row', style: l.active ? '' : 'opacity:.55;' }, [
      icon('userplus', 16),
      el('div', { class: 'grow' }, [
        el('b', { text: l.label || target }),
        el('div', { class: 'muted', text: `${target}${hq ? ' \u00B7 ' + t('ref.owner') + ': ' + l.owner : ''}${l.campaign ? ' \u00B7 ' + l.campaign : ''}` }),
        el('code', { style: 'font-size:12px;user-select:all;', text: url }),
        el('div', { class: 'muted', text: t('ref.counts', { v: l.visits, a: l.applications, m: l.members }) }),
      ]),
      copyBtn(url),
      el('a', { href: `https://wa.me/?text=${encodeURIComponent(t('ref.shareText', { url }))}`, target: '_blank', rel: 'noopener', class: 'btn btn--secondary', text: 'WhatsApp' }),
      (hq || l.owner_id === profile.id) ? el('button', { class: 'btn btn--quiet', text: l.active ? t('ref.deactivate') : t('ref.activate'),
        onclick: async () => { try { await referralLinkToggle(l.id, !l.active); await draw(); } catch (e) { toastError(e?.message || t('errors.save')); } } }) : null,
    ]);
  }

  function copyBtn(url) {
    return el('button', { class: 'btn btn--primary', text: t('ref.copy'), onclick: async () => {
      try { await navigator.clipboard.writeText(url); toast(t('acc.copied')); } catch { toastError(t('errors.save')); }
    } });
  }

  async function creator() {
    const units = await listOrgUnits().catch(() => []);
    const label = el('input', { class: 'input', placeholder: t('ref.labelPh'), maxlength: '120' });
    const campaign = el('input', { class: 'input', placeholder: t('ref.campaignPh'), maxlength: '120' });
    const netSel = el('select', { class: 'select' }, ['WGMN', 'WNNN'].map((n) => el('option', { value: n, text: n })));
    const unitSel = el('select', { class: 'select' }, [el('option', { value: '', text: t('ref.anyUnit') }),
      ...units.filter((u) => u.level !== 'headquarters').sort((a, b) => a.name.localeCompare(b.name)).map((u) => el('option', { value: u.id, text: `${u.name} (${t('v.lvl_' + u.level)})` }))]);
    const roleSel = el('select', { class: 'select' }, [el('option', { value: '', text: t('ref.member') }), ...POSITIONS.map((r) => el('option', { value: r, text: t(`role.${r}`) }))]);
    const go = el('button', { class: 'btn btn--primary', text: t('ref.create'), onclick: async () => {
      go.disabled = true;
      try { await referralLinkEnsure({ hq: true, network: netSel.value, unit: unitSel.value || null, role: roleSel.value || null, label: label.value.trim() || null, campaign: campaign.value.trim() || null }); toast(t('ref.created')); await draw(); }
      catch (e) { toastError(e?.message || t('errors.save')); go.disabled = false; }
    } });
    const fld = (l, n) => el('div', { class: 'field' }, [el('label', { class: 'field__label', text: l }), n]);
    return el('section', { class: 'card' }, [el('h3', { text: t('ref.createTitle') }),
      el('div', { class: 'form-grid' }, [fld(t('v.network'), netSel), fld(t('ref.target'), unitSel), fld(t('st.position'), roleSel),
        fld(t('ref.label'), label), fld(t('ref.campaign'), campaign)]),
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), go])]);
  }

  async function vacancyLinks() {
    const card = el('section', { class: 'card' }, [el('h3', { text: t('ref.vacanciesTitle') }), el('p', { class: 'muted', text: t('ref.vacanciesHint') })]);
    let d;
    try { d = await structureExplorer({ net: net || profile.network || 'WGMN', status: 'vacant', limit: 200 }); }
    catch { d = { rows: [] }; }
    const rows = d.rows || [];
    if (!rows.length) card.append(el('p', { class: 'muted', text: t('ref.noVacancies') }));
    for (const r of rows) {
      const btn = el('button', { class: 'btn btn--secondary', text: t('ref.getLink'), onclick: async () => {
        btn.disabled = true;
        try { const l = await referralLinkEnsure({ network: net || profile.network, unit: r.unit_id, role: r.role, label: `${t(`role.${r.role}`)} \u00B7 ${r.unit}` }); toast(t('ref.created')); await draw(); void l; }
        catch (e) { toastError(e?.message || t('errors.save')); btn.disabled = false; }
      } });
      card.append(el('div', { class: 'rp-row' }, [
        el('span', { class: 'vs-badge vs-badge--red', text: t('v.seatVacant') }),
        el('div', { class: 'grow' }, [el('b', { text: t(`role.${r.role}`) }), el('div', { class: 'muted', text: `${r.unit}${r.parent ? ' \u00B7 ' + r.parent : ''}${r.country && r.level !== 'country' ? ' \u00B7 ' + r.country : ''}` })]),
        btn]));
    }
    const gen = el('button', { class: 'btn btn--primary', text: t('ref.generalLink'), onclick: async () => {
      gen.disabled = true;
      try { await referralLinkEnsure({ network: net || profile.network, label: t('ref.generalLabel') }); toast(t('ref.created')); await draw(); }
      catch (e) { toastError(e?.message || t('errors.save')); gen.disabled = false; }
    } });
    card.append(el('div', { class: 'row', style: 'margin-top:8px;' }, [el('span', { class: 'muted grow', text: t('ref.generalHint') }), gen]));
    return card;
  }
}
