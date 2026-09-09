/**
 * WDOS Spotlight Review — Phase 102. Replaces the SQL-Editor-only
 * workflow (Phase 99) with a real screen: HQ browses nominations by
 * status and scores, records consent, publishes, or holds them here.
 * The backend engine (migration 087) is unchanged — this page is a
 * front door onto RPCs that already worked from the SQL Editor.
 */
import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import { db } from '../core/db.js';
import { openModal, closeModal } from '../components/modal.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const STATUS_TABS = ['submitted', 'screening', 'scoring', 'consent_pending',
  'held', 'published'];

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.spotlightReview',
  });
  const out = shell.outlet;
  clear(out);
  out.append(el('h1', { text: t('spot.title') }));
  out.append(el('p', { class: 'muted mb-4', text: t('spot.sub') }));

  const tabsEl = el('div', { class: 'row mb-3', style: 'gap:6px;flex-wrap:wrap;' });
  const listBox = el('div');
  out.append(tabsEl, listBox);

  let active = 'submitted';
  const buttons = {};
  STATUS_TABS.forEach((s) => {
    const b = el('button', { class: 'btn btn--secondary',
      text: t(`spot.status.${s}`) });
    b.addEventListener('click', () => { active = s; paint(); });
    buttons[s] = b;
    tabsEl.append(b);
  });

  async function paint() {
    STATUS_TABS.forEach((s) => {
      buttons[s].classList.toggle('btn--primary', s === active);
      buttons[s].classList.toggle('btn--secondary', s !== active);
    });
    clear(listBox);
    listBox.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));

    const { data, error } = await db().from('spotlight_nominations')
      .select(`id, category, verified_contribution, evidence_summary,
        other_contributors, status, held_reason, score_total,
        score_mission, score_impact, score_consistency, score_character,
        score_unseen, public_consent, created_at,
        nominee:profiles!spotlight_nominations_nominee_id_fkey(id,first_name,last_name),
        nominator:profiles!spotlight_nominations_nominator_id_fkey(first_name,last_name)`)
      .eq('status', active).order('created_at', { ascending: true });

    clear(listBox);
    if (error) {
      listBox.append(el('p', { class: 'muted', text: t('errors.load') }));
      return;
    }
    if (!data || !data.length) {
      listBox.append(el('p', { class: 'muted', text: t('spot.none') }));
      return;
    }
    data.forEach((nom) => listBox.append(nomCard(nom)));
  }

  function nomCard(nom) {
    const card = el('div', { class: 'card mb-3' });
    const who = nom.nominee
      ? `${nom.nominee.first_name} ${nom.nominee.last_name}` : t('spot.unknown');
    const byWhom = nom.nominator
      ? `${nom.nominator.first_name} ${nom.nominator.last_name}` : '—';
    card.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
        <b style="flex:1;min-width:160px;">${esc(who)}</b>
        <span class="badge badge--pipeline">${esc(nom.category)}</span>
        ${nom.score_total != null
          ? `<span class="badge badge--active">${esc(String(nom.score_total))}/25</span>` : ''}
      </div>
      <p style="margin:8px 0 4px;font-size:14px;">${esc(nom.verified_contribution)}</p>
      <p class="muted" style="font-size:12px;">${esc(t('spot.evidence'))}: ${esc(nom.evidence_summary)}</p>
      ${nom.other_contributors ? `<p class="muted" style="font-size:12px;">${esc(t('spot.others'))}: ${esc(nom.other_contributors)}</p>` : ''}
      <p class="muted" style="font-size:11px;">${esc(t('spot.nominatedBy', { name: byWhom }))} · ${esc(fmtDate(nom.created_at))}</p>
      ${nom.held_reason ? `<p style="color:#dc2626;font-size:12px;">${esc(nom.held_reason)}</p>` : ''}
    `;
    const actions = el('div', { class: 'row', style: 'gap:8px;margin-top:8px;flex-wrap:wrap;' });
    if (active === 'submitted' || active === 'screening' || active === 'scoring') {
      actions.append(btn(t('spot.score'), () => scoreModal(nom)));
    }
    if (active === 'consent_pending') {
      actions.append(btn(t('spot.consentYes'), () => doConsent(nom.id, true)));
      actions.append(btn(t('spot.consentNo'), () => doConsent(nom.id, false)));
      actions.append(btn(t('spot.publish'), () => publishModal(nom)));
    }
    if (active !== 'published' && active !== 'held') {
      actions.append(btn(t('spot.hold'), () => holdModal(nom.id), true));
    }
    card.append(actions);
    return card;
  }

  function btn(label, onClick, quiet) {
    const b = el('button', { class: quiet ? 'btn btn--quiet' : 'btn btn--secondary',
      text: label });
    b.addEventListener('click', onClick);
    return b;
  }

  function scoreModal(nom) {
    const mk = (labelKey) => {
      const sel = el('select', { class: 'input' }, [
        el('option', { value: '5', text: '5' }),
        el('option', { value: '3', text: '3' }),
        el('option', { value: '1', text: '1' }),
      ]);
      return { row: el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t(labelKey) }), sel]), sel };
    };
    const mission = mk('spot.scMission');
    const impact = mk('spot.scImpact');
    const consistency = mk('spot.scConsistency');
    const character = mk('spot.scCharacter');
    const unseen = mk('spot.scUnseen');
    const err = el('p', { class: 'field__error', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('spot.scoreSubmit') });
    const form = el('form', { onsubmit: async (e) => {
      e.preventDefault();
      submit.disabled = true;
      try {
        const { data, error } = await db().rpc('score_spotlight_nomination', {
          p_nomination: nom.id,
          p_mission: Number(mission.sel.value), p_impact: Number(impact.sel.value),
          p_consistency: Number(consistency.sel.value),
          p_character: Number(character.sel.value),
          p_unseen: Number(unseen.sel.value) });
        if (error) throw error;
        toast(data.qualifies ? t('spot.scoreQualifies', { n: data.total })
                              : t('spot.scoreHeld', { n: data.total }));
        closeModal(); paint();
      } catch (err2) {
        err.textContent = err2?.message || t('errors.save'); err.hidden = false;
        submit.disabled = false;
      }
    } }, [
      el('p', { class: 'muted mb-2', text: t('spot.scoreHint') }),
      mission.row, impact.row, consistency.row, character.row, unseen.row,
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    openModal(t('spot.scoreModalTitle'), form);
  }

  async function doConsent(id, given) {
    try {
      const { error } = await db().rpc('record_spotlight_consent',
        { p_nomination: id, p_public_consent: given });
      if (error) throw error;
      toast(given ? t('spot.consentRecordedYes') : t('spot.consentRecordedNo'));
      paint();
    } catch (err) { toastError(err?.message || t('errors.save')); }
  }

  function publishModal(nom) {
    const impact = el('textarea', { class: 'input', rows: '3',
      placeholder: t('spot.publishImpactPh') });
    const err = el('p', { class: 'field__error', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('spot.publishSubmit') });
    const form = el('form', { onsubmit: async (e) => {
      e.preventDefault();
      submit.disabled = true;
      try {
        const { error } = await db().rpc('publish_spotlight',
          { p_nomination: nom.id, p_verified_impact_final: impact.value.trim() });
        if (error) throw error;
        toast(t('spot.published'));
        closeModal(); paint();
      } catch (err2) {
        err.textContent = err2?.message || t('errors.save'); err.hidden = false;
        submit.disabled = false;
      }
    } }, [
      el('p', { class: 'muted mb-2', text: t('spot.publishHint') }),
      impact, err,
      el('div', { class: 'row mt-2' }, [el('span', { class: 'grow' }), submit]),
    ]);
    openModal(t('spot.publishModalTitle'), form);
  }

  function holdModal(id) {
    const reason = el('textarea', { class: 'input', rows: '2',
      placeholder: t('spot.holdReasonPh') });
    const err = el('p', { class: 'field__error', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('spot.holdSubmit') });
    const form = el('form', { onsubmit: async (e) => {
      e.preventDefault();
      submit.disabled = true;
      try {
        const { error } = await db().rpc('hold_spotlight_nomination',
          { p_nomination: id, p_reason: reason.value.trim() });
        if (error) throw error;
        toast(t('spot.held'));
        closeModal(); paint();
      } catch (err2) {
        err.textContent = err2?.message || t('errors.save'); err.hidden = false;
        submit.disabled = false;
      }
    } }, [reason, err,
      el('div', { class: 'row mt-2' }, [el('span', { class: 'grow' }), submit])]);
    openModal(t('spot.holdModalTitle'), form);
  }

  await paint();
}
