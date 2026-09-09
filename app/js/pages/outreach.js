/**
 * WDOS Institute Outreach — Phase 106. Holds the 46-organisation
 * invitation list for the Pioneer WODDI Institute Learning Cohort,
 * sends the founder's letter through the existing email layer, and
 * tracks each organisation from Sent through Onboarded.
 */
import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import { db, outreachSummary, sendOutreachBatch, sendOutreachOne,
  setOutreachStatus, getEmailStatus } from '../core/db.js';
import { openModal, closeModal } from '../components/modal.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const STATUS_ORDER = ['pending', 'held', 'sent', 'bounced', 'replied',
  'nominations_received', 'onboarded'];
const STATUS_CLASS = {
  pending: 'inactive', held: 'pipeline', sent: 'pipeline',
  bounced: 'exited', replied: 'active', nominations_received: 'active',
  onboarded: 'active',
};

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.outreach',
  });
  const out = shell.outlet;
  clear(out);
  out.append(el('h1', { text: t('out.title') }));
  out.append(el('p', { class: 'muted mb-4', text: t('out.sub') }));

  const banner = el('div');
  const tilesEl = el('div', { class: 'row mb-4', style:
    'gap:10px;flex-wrap:wrap;' });
  const controlsEl = el('div', { class: 'row mb-3', style:
    'gap:10px;flex-wrap:wrap;align-items:center;' });
  const listBox = el('div');
  out.append(banner, tilesEl, controlsEl, listBox);

  // email-off banner, checked once up front
  try {
    const es = await getEmailStatus();
    if (!es.enabled) {
      const b = el('div', { class: 'card', style:
        'background:#FEF3C7;border:1px solid #F59E0B;margin-bottom:14px;' });
      b.innerHTML = `<b>${esc(t('out.emailOffTitle'))}</b>
        <p style="margin:4px 0 0;font-size:13px;">${esc(t('out.emailOffBody'))}
        <a href="#/settings">${esc(t('out.emailOffLink'))}</a></p>`;
      banner.append(b);
    }
  } catch { /* non-HQ or transient — the send call itself will explain */ }

  let filterStatus = '';
  let filterCountry = '';
  let filterLanguage = '';
  let filterNeedsVerification = false;

  async function paintTiles() {
    clear(tilesEl);
    const summary = await outreachSummary().catch(() => ({}));
    STATUS_ORDER.forEach((s) => {
      const tile = el('div', { class: 'card', style:
        'min-width:120px;text-align:center;padding:14px;' });
      tile.innerHTML = `<div class="muted" style="font-size:11px;
        text-transform:uppercase;">${esc(t(`out.status.${s}`))}</div>
        <div style="font-size:26px;font-weight:800;">${esc(String(summary[s] || 0))}</div>`;
      tilesEl.append(tile);
    });
  }

  function buildControls() {
    clear(controlsEl);
    const sendBtn = el('button', { class: 'btn btn--primary',
      text: t('out.sendBatch') });
    sendBtn.addEventListener('click', async () => {
      sendBtn.disabled = true;
      try {
        const r = await sendOutreachBatch(20);
        if (r.error) { toastError(r.error); }
        else {
          toast(t('out.batchResult', { sent: r.sent, attempted: r.attempted,
            remaining: r.remaining_pending }));
          toast(t('out.batchNote'));
        }
        await paintTiles(); await paintList();
      } catch (err) { toastError(err?.message || t('errors.save')); }
      sendBtn.disabled = false;
    });

    const statusSel = el('select', { class: 'input' },
      [el('option', { value: '', text: t('out.filterAllStatus') }),
        ...STATUS_ORDER.map((s) => el('option', { value: s,
          text: t(`out.status.${s}`) }))]);
    statusSel.addEventListener('change', () => {
      filterStatus = statusSel.value; paintList();
    });

    const verifySel = el('select', { class: 'input' }, [
      el('option', { value: '', text: t('out.filterAllContacts') }),
      el('option', { value: 'yes', text: t('out.filterNeedsVerification') }),
    ]);
    verifySel.addEventListener('change', () => {
      filterNeedsVerification = verifySel.value === 'yes'; paintList();
    });

    controlsEl.append(sendBtn, statusSel, verifySel);
  }

  async function paintList() {
    clear(listBox);
    listBox.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));

    let q = db().from('outreach_contacts')
      .select('id, organisation, category, country, language, email, ' +
        'leader_name, leader_title, status, needs_verification, sent_at, notes')
      .order('organisation', { ascending: true });
    if (filterStatus) q = q.eq('status', filterStatus);
    if (filterNeedsVerification) q = q.eq('needs_verification', true);
    const { data, error } = await q;

    clear(listBox);
    if (error) {
      listBox.append(el('p', { class: 'muted', text: t('errors.load') }));
      return;
    }
    if (!data || !data.length) {
      listBox.append(el('p', { class: 'muted', text: t('out.none') }));
      return;
    }

    const card = el('div', { class: 'card', style: 'overflow-x:auto;' });
    const rowsHtml = data.map((c) => `<tr>
      <td><b>${esc(c.organisation)}</b><br>
        <span class="muted" style="font-size:11px;">${esc(c.category || '')}</span></td>
      <td>${esc(c.country || '—')}</td>
      <td><span class="badge badge--pipeline">${esc((c.language || 'en').toUpperCase())}</span></td>
      <td>${esc(c.leader_name || '—')}<br>
        <span class="muted" style="font-size:11px;">${esc(c.leader_title || '')}</span></td>
      <td style="font-size:12px;">${esc(c.email)}${c.needs_verification
        ? ` <span class="badge badge--pipeline" style="font-size:9px;">${esc(t('out.needsVerification'))}</span>` : ''}</td>
      <td><span class="badge badge--${STATUS_CLASS[c.status] || 'inactive'}">${esc(t(`out.status.${c.status}`))}</span></td>
      <td class="muted" style="font-size:12px;">${c.sent_at ? esc(fmtDate(c.sent_at)) : '—'}</td>
      <td data-actions="${esc(c.id)}"></td>
    </tr>`).join('');
    card.innerHTML = `<table class="table">
      <thead><tr>
        <th>${esc(t('out.colOrg'))}</th>
        <th>${esc(t('out.colCountry'))}</th>
        <th>${esc(t('out.colLang'))}</th>
        <th>${esc(t('out.colLeader'))}</th>
        <th>${esc(t('out.colEmail'))}</th>
        <th>${esc(t('out.colStatus'))}</th>
        <th>${esc(t('out.colSent'))}</th>
        <th>${esc(t('out.colActions'))}</th>
      </tr></thead><tbody>${rowsHtml}</tbody></table>`;
    listBox.append(card);

    data.forEach((c) => {
      const cell = card.querySelector(`td[data-actions="${CSS.escape(c.id)}"]`);
      if (!cell) return;
      const wrap = el('div', { class: 'row', style: 'gap:4px;flex-wrap:wrap;' });
      if (c.status === 'held' || c.status === 'pending') {
        wrap.append(smallBtn(t('out.sendNow'), () => sendOne(c)));
      }
      if (c.status === 'held') {
        wrap.append(smallBtn(t('out.editEmail'), () => editEmailModal(c)));
      }
      if (c.status === 'sent') {
        wrap.append(smallBtn(t('out.markBounced'),
          () => quickStatus(c.id, 'bounced')));
        wrap.append(smallBtn(t('out.markReplied'),
          () => quickStatus(c.id, 'replied')));
      }
      if (c.status === 'replied') {
        wrap.append(smallBtn(t('out.markNominations'),
          () => quickStatus(c.id, 'nominations_received')));
      }
      if (c.status === 'nominations_received') {
        wrap.append(smallBtn(t('out.markOnboarded'),
          () => quickStatus(c.id, 'onboarded')));
      }
      cell.append(wrap);
    });
  }

  function smallBtn(label, onClick) {
    const b = el('button', { class: 'btn btn--quiet',
      style: 'font-size:11px;padding:4px 8px;', text: label });
    b.addEventListener('click', onClick);
    return b;
  }

  async function sendOne(c) {
    try {
      const ok = await sendOutreachOne(c.id);
      if (ok) toast(t('out.sentOne', { name: c.organisation }));
      else toastError(t('out.sendFailed'));
      await paintTiles(); await paintList();
    } catch (err) { toastError(err?.message || t('errors.save')); }
  }

  async function quickStatus(id, status) {
    try {
      await setOutreachStatus(id, status);
      toast(t('out.statusUpdated'));
      await paintTiles(); await paintList();
    } catch (err) { toastError(err?.message || t('errors.save')); }
  }

  function editEmailModal(c) {
    const input = el('input', { class: 'input', value: c.email });
    const err = el('p', { class: 'field__error', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('out.saveAndRelease') });
    const form = el('form', { onsubmit: async (e) => {
      e.preventDefault();
      if (!input.value.includes('@')) {
        err.textContent = t('out.invalidEmail'); err.hidden = false; return;
      }
      submit.disabled = true;
      try {
        await setOutreachStatus(c.id, 'pending', input.value.trim());
        toast(t('out.emailUpdated'));
        closeModal(); await paintTiles(); await paintList();
      } catch (err2) {
        err.textContent = err2?.message || t('errors.save'); err.hidden = false;
        submit.disabled = false;
      }
    } }, [
      el('p', { class: 'muted mb-2', text: t('out.editEmailHint', { name: c.organisation }) }),
      input, err,
      el('div', { class: 'row mt-2' }, [el('span', { class: 'grow' }), submit]),
    ]);
    openModal(t('out.editEmailTitle'), form);
  }

  buildControls();
  await paintTiles();
  await paintList();
}
