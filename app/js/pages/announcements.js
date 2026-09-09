import { el, esc, clear , personLabel } from '../core/dom.js';
import { t, fmtDate, fmtDateTime, fmtNumber } from '../core/i18n.js';
import {
  listAnnouncements, postAnnouncement, markAnnouncementRead,
  getAnnouncementReach, listOrgUnits, getMyRoles,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const PAGE_SIZE = 20;
const PRIO_BADGE = { normal: 'neutral', important: 'paused', urgent: 'exited' };

export async function render(root, _params, ctx) {
  // Phase 89: activation evidence — the system saw this visit.
  import('../core/db.js').then(({ logJourneyEvent }) =>
    logJourneyEvent('announcement_opened'));

  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.announcements',
  });
  const out = shell.outlet;
  const state = { page: 0 };

  let isLeader = false;
  try { isLeader = (await getMyRoles()).length > 0; } catch { /* feed still works */ }

  const newBtn = isLeader
    ? el('button', { class: 'btn btn--primary', text: t('ann.new'),
        onclick: () => { formCard.hidden = !formCard.hidden; } })
    : null;
  const formCard = isLeader ? await buildForm() : el('div');
  formCard.hidden = true;

  const listArea = el('div');
  out.append(
    el('div', { class: 'toolbar' }, [el('span', { class: 'grow' }),
      ...(newBtn ? [newBtn] : [])]),
    formCard, listArea
  );
  await load();
  return shell.teardown;

  async function load() {
    clear(listArea);
    listArea.append(el('div', { class: 'state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    try {
      const { rows, total } = await listAnnouncements({ ...state, pageSize: PAGE_SIZE });
      clear(listArea);
      if (rows.length === 0) {
        listArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('ann.emptyTitle') }),
          el('p', { text: t('ann.emptyHint') }),
        ]));
        return;
      }
      for (const a of rows) listArea.append(annCard(a));
      listArea.append(pager(total));
    } catch {
      clear(listArea);
      listArea.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('p', { text: t('errors.loadHint') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'), onclick: load }),
      ]));
    }
  }

  function annCard(a) {
    const card = el('div', { class: 'card mb-4' });
    const head = el('div', { class: 'card__head' });
    head.innerHTML = `
      <div>
        <h2>${esc(a.title)}
          ${!a.read ? `<span class="badge badge--pipeline">${esc(t('ann.unread'))}</span>` : ''}
        </h2>
        <span class="muted">
          ${esc(fmtDateTime(a.created_at))}
          · ${esc(t('ann.by', { name: personLabel(a.author) }))}
          ${a.network ? ' · ' + esc(a.network) : ''}
          ${a.audience && a.audience !== 'all'
            ? ' · ' + esc(t(`ann.audBadge.${a.audience}`)) : ''}
        </span>
      </div>
      <span class="badge badge--${PRIO_BADGE[a.priority]}">
        ${esc(t(`annprio.${a.priority}`))}</span>`;
    card.append(head, el('p', { text: a.body,
      style: 'white-space:pre-wrap;' }));

    const actions = el('div', { class: 'row mt-4' });
    if (!a.read) {
      actions.append(el('button', {
        class: 'btn btn--secondary', text: t('ann.markRead'),
        onclick: async (e) => {
          e.target.disabled = true;
          try {
            await markAnnouncementRead(a.id);
            a.read = true;
            card.replaceWith(annCard(a));
          } catch { toastError(t('errors.save')); e.target.disabled = false; }
        },
      }));
    }
    if (isLeader) {
      const reachBtn = el('button', { class: 'btn btn--quiet',
        text: t('ann.reach'),
        onclick: async () => {
          reachBtn.disabled = true;
          try {
            const r = await getAnnouncementReach(a.id);
            reachBtn.replaceWith(el('span', { class: 'muted',
              text: t('ann.reachDetail', {
                r: fmtNumber(r.reads), n: fmtNumber(r.audience) }) }));
          } catch {
            reachBtn.disabled = false;
            // Not the author/manager of this one — nothing to show.
          }
        } });
      actions.append(reachBtn);
    }
    card.append(actions);
    return card;
  }

  function pager(total) {
    const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    return el('div', { class: 'row mt-4' }, [
      el('span', { class: 'muted grow',
        text: t('ann.count', { n: fmtNumber(total) }) }),
      el('button', { class: 'btn btn--quiet', text: t('app.prev'),
        disabled: state.page === 0 || null,
        onclick: () => { state.page -= 1; load(); } }),
      el('span', { class: 'muted', text: `${state.page + 1} / ${pages}` }),
      el('button', { class: 'btn btn--quiet', text: t('app.next'),
        disabled: state.page >= pages - 1 || null,
        onclick: () => { state.page += 1; load(); } }),
    ]);
  }

  async function buildForm() {
    let units = [];
    try { units = await listOrgUnits(); } catch { /* surfaced on submit */ }
    const title = el('input', { class: 'input', maxlength: '160' });
    const body = el('textarea', { class: 'input', rows: '5', maxlength: '8000' });
    const unitSel = el('select', { class: 'select' },
      units.map((u) => el('option', { value: u.id,
        text: `${t(`org.${u.level}`)} — ${u.name}` })));
    const network = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('ann.bothNetworks') }),
      el('option', { value: 'WGMN', text: 'WGMN' }),
      el('option', { value: 'WNNN', text: 'WNNN' }),
    ]);
    const audience = el('select', { class: 'select' }, [
      el('option', { value: 'all', text: t('ann.audAll') }),
      el('option', { value: 'leaders', text: t('ann.audLeaders') }),
      el('option', { value: 'intake', text: t('ann.audIntake') }),
    ]);
    const prio = el('select', { class: 'select' },
      ['normal', 'important', 'urgent'].map((p) =>
        el('option', { value: p, selected: p === 'normal' || null,
          text: t(`annprio.${p}`) })));
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('ann.post') });

    const form = el('form', { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (title.value.trim().length < 3) { fail(t('tasks.errTitle')); return; }
      if (!body.value.trim()) { fail(t('ann.errBody')); return; }
      err.hidden = true;
      submit.disabled = true;
      try {
        await postAnnouncement({
          title: title.value.trim(),
          body: body.value.trim(),
          org_unit_id: unitSel.value,
          network: network.value,
          priority: prio.value,
          audience: audience.value,
        });
        toast(t('ann.posted'));
        form.reset();
        formCard.hidden = true;
        state.page = 0;
        load();
      } catch (e2) {
        fail(String(e2?.message ?? '').includes('row-level security')
          ? t('ann.errScope') : t('errors.save'));
      } finally { submit.disabled = false; }
      function fail(msg) { err.textContent = msg; err.hidden = false; }
    } }, [
      el('div', { class: 'form-grid' }, [
        wrap(t('ann.title'), title),
        wrap(t('ann.audienceUnit'), unitSel),
        wrap(t('ann.network'), network),
        wrap(t('tasks.priority'), prio),
        wrap(t('ann.audience'), audience),
      ]),
      wrap(t('ann.body'), body),
      el('p', { class: 'field__hint', text: t('ann.subtreeHint') }),
      el('p', { class: 'field__hint', text: t('ann.audienceHint') }),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    return el('div', { class: 'card mb-4' }, [
      el('div', { class: 'card__head' }, [el('h2', { text: t('ann.new') })]),
      form,
    ]);
  }
}

function wrap(label, control) {
  return el('div', { class: 'field' }, [
    el('label', { class: 'field__label', text: label }), control,
  ]);
}
