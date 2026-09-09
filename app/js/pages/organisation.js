import { el, esc, clear, debounce , personLabel } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import {
  listOrgUnits, createOrgUnit, listUnitLeaders, appointLeader,
  endAppointment, searchAppointableMembers,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const APPOINTABLE = [
  'country_rep', 'deputy_country_rep', 'state_coordinator',
  'assistant_state_coordinator', 'district_coordinator', 'chapter_lead',
];

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.organisation',
  });
  const out = shell.outlet;

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let units;
  try {
    units = await listOrgUnits();
  } catch {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('errors.loadTitle') }),
      el('p', { text: t('errors.loadHint') }),
      el('button', { class: 'btn btn--quiet', text: t('app.retry'),
        onclick: () => render(root, _params, ctx) }),
    ]));
    return shell.teardown;
  }

  clear(out);
  const byParent = new Map();
  for (const u of units) {
    const k = u.parent_id ?? 'root';
    if (!byParent.has(k)) byParent.set(k, []);
    byParent.get(k).push(u);
  }

  const treeCard = el('div', { class: 'card' }, [
    el('div', { class: 'card__head' }, [el('h2', { text: t('org.treeTitle') })]),
  ]);
  const detail = el('div', { class: 'mt-4' });
  treeCard.append(tree('root', 0));
  out.append(treeCard, detail);
  return shell.teardown;

  function tree(parentKey, depth) {
    const wrap = el('div');
    for (const u of byParent.get(parentKey) ?? []) {
      const row = el('div', {
        class: 'row',
        style: `padding:6px 0 6px ${depth * 20}px;`,
      }, [
        el('button', {
          class: 'btn btn--quiet', style: 'min-height:32px;padding:4px 12px;',
          text: `${u.name}`,
          onclick: () => openUnit(u),
        }),
        el('span', { class: 'muted', text: t(`org.${u.level}`) }),
      ]);
      wrap.append(row, tree(u.id, depth + 1));
    }
    return wrap;
  }

  async function openUnit(unit) {
    clear(detail);
    detail.append(el('div', { class: 'card state' }, [
      el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
    ]));
    let leaders;
    try {
      leaders = await listUnitLeaders(unit.id, { includePast: true });
    } catch {
      clear(detail);
      detail.append(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: () => openUnit(unit) }),
      ]));
      return;
    }
    drawUnit(unit, leaders);
  }

  function drawUnit(unit, leaders) {
    clear(detail);
    const card = el('div', { class: 'card' });
    card.append(el('div', { class: 'card__head' }, [
      el('h2', { text: unit.name }),
      el('span', { class: 'muted', text: t(`org.${unit.level}`) }),
    ]));

    /* ---- current + past leadership ---- */
    const current = leaders.filter((l) => !l.ends_at);
    const past = leaders.filter((l) => l.ends_at);

    card.append(el('h3', { class: 'mb-4', text: t('org.currentLeaders') }));
    if (current.length === 0) {
      card.append(el('p', { class: 'muted', text: t('org.noLeaders') }));
    }
    for (const l of current) {
      const endReason = el('input', {
        class: 'input', maxlength: '1000', style: 'flex:2;',
        placeholder: t('recruit.reasonPlaceholder'),
      });
      card.append(el('div', { class: 'row mb-4' }, [
        el('div', { class: 'grow' }, [
          el('strong', { text: personLabel(l.person) }),
          el('div', { class: 'muted',
            text: `${t(`role.${l.role}`)} · ${t('org.since',
              { d: fmtDate(l.starts_at) })}` }),
        ]),
        endReason,
        el('button', {
          class: 'btn btn--danger', text: t('org.endRole'),
          onclick: async () => {
            if (endReason.value.trim().length < 5) {
              toastError(t('recruit.errReason')); return;
            }
            try {
              await endAppointment(l.id, endReason.value.trim());
              toast(t('org.ended'));
              openUnit(unit);
            } catch (err) { toastError(mapError(err)); }
          },
        }),
      ]));
    }

    /* ---- appointment form ---- */
    card.append(el('h3', { class: 'mb-4 mt-4', text: t('org.appointTitle') }));
    const search = el('input', {
      class: 'input', type: 'search',
      placeholder: t('org.searchMember'), 'aria-label': t('org.searchMember'),
    });
    const results = el('select', { class: 'select', size: '4' });
    const roleSel = el('select', { class: 'select' },
      APPOINTABLE.map((r) => el('option', { value: r, text: t(`role.${r}`) })));
    const reason = el('input', {
      class: 'input', maxlength: '1000',
      placeholder: t('recruit.reasonPlaceholder'),
    });
    const appointBtn = el('button', {
      class: 'btn btn--primary', text: t('org.appoint'),
      onclick: async () => {
        if (!results.value) { toastError(t('org.errPickMember')); return; }
        if (reason.value.trim().length < 5) {
          toastError(t('recruit.errReason')); return;
        }
        appointBtn.disabled = true;
        try {
          await appointLeader(results.value, roleSel.value, unit.id,
            reason.value.trim());
          toast(t('org.appointed'));
          openUnit(unit);
        } catch (err) { toastError(mapError(err)); }
        finally { appointBtn.disabled = false; }
      },
    });
    search.addEventListener('input', debounce(async () => {
      try {
        const rows = await searchAppointableMembers(search.value.trim());
        clear(results);
        for (const r of rows) {
          results.append(el('option', { value: r.id,
            text: `${r.first_name} ${r.last_name} — ${r.email}` }));
        }
        if (rows.length === 0) {
          results.append(el('option', { value: '', disabled: true,
            text: t('org.noEligible') }));
        }
      } catch { toastError(t('errors.load')); }
    }));
    card.append(
      el('div', { class: 'form-grid' }, [
        el('div', { class: 'field' }, [
          el('label', { class: 'field__label', text: t('org.searchMember') }),
          search, results,
          el('p', { class: 'field__hint', text: t('org.eligibleHint') }),
        ]),
        el('div', { class: 'field' }, [
          el('label', { class: 'field__label', text: t('org.role') }),
          roleSel, reason,
        ]),
      ]),
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), appointBtn])
    );

    /* ---- create child unit ---- */
    if (unit.level !== 'chapter') {
      card.append(el('h3', { class: 'mb-4 mt-4', text: t('org.addUnitTitle') }));
      const name = el('input', { class: 'input', maxlength: '120',
        placeholder: t('org.unitName') });
      const iso = el('input', { class: 'input', maxlength: '2',
        placeholder: t('org.isoHint'), style: 'max-width:120px;' });
      const showIso = unit.level === 'headquarters';
      const addBtn = el('button', {
        class: 'btn btn--secondary', text: t('org.addUnit'),
        onclick: async () => {
          if (name.value.trim().length < 2) {
            toastError(t('org.errUnitName')); return;
          }
          try {
            const created = await createOrgUnit(unit.id, name.value.trim(),
              showIso ? iso.value.trim() : null);
            units.push(created);
            const k = created.parent_id;
            if (!byParent.has(k)) byParent.set(k, []);
            byParent.get(k).push(created);
            treeCard.lastChild.replaceWith(tree('root', 0));
            toast(t('org.unitAdded'));
            name.value = '';
          } catch (err) { toastError(mapError(err)); }
        },
      });
      card.append(el('div', { class: 'row' },
        showIso ? [name, iso, addBtn] : [name, addBtn]));
    }

    /* ---- history ---- */
    if (past.length > 0) {
      card.append(el('h3', { class: 'mb-4 mt-4', text: t('org.pastLeaders') }));
      for (const l of past) {
        card.append(el('p', { class: 'muted',
          text: personLabel(l.person) + ' \u2014 ' +
            `${t(`role.${l.role}`)} (${fmtDate(l.starts_at)} → ` +
            `${fmtDate(l.ends_at)})` }));
      }
    }

    detail.append(card);
  }
}

function mapError(err) {
  const m = String(err?.message ?? '');
  if (m.includes('junior to your own')) return t('org.errSeniority');
  if (m.includes('good standing')) return t('org.errStanding');
  if (m.includes('already holds')) return t('org.errDuplicateRole');
  if (m.includes('more senior role')) return t('org.errEndSeniority');
  if (m.includes('State Coordinator role or above')) return t('org.errCreateAuth');
  if (m.includes('reason is required') || m.includes('Reason'))
    return t('recruit.errReason');
  return t('errors.save');
}
