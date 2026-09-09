import { el, clear } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  listActivationMilestones, getJourney, getJourneyProgress,
  completeMilestone, extendActivation,
} from '../core/db.js';
import { toast, toastError } from './toast.js';

/**
 * Renders the activation journey card for a profile, or nothing if no
 * journey exists. mode: 'self' (the person) | 'leader' (marking authority).
 */
export async function journeyCard(profileId, mode) {
  let journey;
  try { journey = await getJourney(profileId); } catch { return null; }
  if (!journey) return null;

  const card = el('div', { class: 'card mt-4' });
  await draw();
  return card;

  async function draw() {
    let milestones, progress;
    try {
      [milestones, progress] = await Promise.all([
        listActivationMilestones(),
        getJourneyProgress(journey.id),
      ]);
    } catch {
      card.replaceChildren(el('p', { class: 'field__error',
        text: t('errors.load') }));
      return;
    }
    const done = new Map(progress.map((p) => [p.milestone_id, p]));
    const required = milestones.filter((m) => m.is_required);
    const doneRequired = required.filter((m) => done.has(m.id)).length;
    (async () => {
      try {
        const { programmeState } = await import('../core/db.js');
        const st = String(await programmeState());
        if (st !== 'open') {
          card.prepend(el('p', { class: 'muted', style:
            'border-left:3px solid var(--lime,#7CB518);padding-left:10px;',
            text: t(`prog.${st}Body`) }));
        }
      } catch { /* calendar line optional */ }
    })();
    const deadline = journey.extended_until ?? journey.due_at;
    const daysLeft = Math.ceil(
      (new Date(deadline) - Date.now()) / 86400000);

    clear(card);
    const state =
      journey.status !== 'in_progress'
        ? t(`journey.${journey.status}`)
        : daysLeft >= 0
          ? t('journey.daysLeft', { n: fmtNumber(daysLeft) })
          : t('journey.overdue', { n: fmtNumber(-daysLeft) });
    card.append(el('div', { class: 'card__head' }, [
      el('h2', { text: t('journey.title') }),
      el('span', {
        class: `badge badge--${
          journey.status === 'completed' ? 'active'
          : journey.status !== 'in_progress' ? 'exited'
          : daysLeft < 0 ? 'exited' : 'pipeline'}`,
        text: state }),
    ]));
    card.append(el('p', { class: 'muted', text: t('journey.progress', {
      done: fmtNumber(doneRequired), total: fmtNumber(required.length),
      due: fmtDate(deadline) }) }));

    for (const m of milestones) {
      const p = done.get(m.id);
      const row = el('p', { style: 'margin:6px 0;' }, [
        el('span', { text: (p ? '\u2705 ' : '\u2B1C ') + m.name +
          (m.is_required ? '' : ` (${t('journey.optional')})`) }),
      ]);
      if (p) {
        row.append(el('span', { class: 'muted',
          text: ` \u2014 ${fmtDate(p.completed_at)}` }));
      } else if (journey.status === 'in_progress'
          && (mode === 'leader' || m.self_service)) {
        row.append(el('button', {
          class: 'btn btn--quiet',
          style: 'min-height:26px;padding:1px 10px;margin-left:8px;',
          text: mode === 'leader' ? t('journey.markDone') : t('journey.confirm'),
          onclick: async (e) => {
            e.target.disabled = true;
            try {
              await completeMilestone(journey.id, m.id, null);
              journey = await (await import('../core/db.js'))
                .getJourney(profileId) ?? journey;
              toast(t('journey.marked'));
              draw();
            } catch (err) {
              const msg = String(err?.message ?? '');
              toastError(msg.includes('authority') ? t('journey.errAuth')
                : (msg || t('errors.save')));
              e.target.disabled = false;
            }
          } }));
      }
      card.append(row);
    }

    if (mode === 'leader' && journey.status === 'in_progress') {
      const until = el('input', { class: 'input', type: 'date' });
      const reason = el('input', { class: 'input', maxlength: '1000',
        placeholder: t('journey.extendReason') });
      card.append(el('div', { class: 'row mt-4' }, [
        until, reason,
        el('button', { class: 'btn btn--quiet', text: t('journey.extend'),
          onclick: async (e) => {
            if (!until.value || reason.value.trim().length < 5) {
              toastError(t('recruit.errReason')); return;
            }
            e.target.disabled = true;
            try {
              journey = await extendActivation(journey.id,
                new Date(until.value + 'T23:59:59').toISOString(),
                reason.value.trim());
              toast(t('journey.extended'));
              draw();
            } catch (err2) { toastError(err2?.message || t('errors.save')); }
            finally { e.target.disabled = false; }
          } }),
      ]));
    }
  }
}
