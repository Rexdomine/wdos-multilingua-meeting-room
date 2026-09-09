import { el, esc, clear, debounce } from '../core/dom.js';
import { t, fmtDate, fmtNumber } from '../core/i18n.js';
import {
  listProgrammes, updateProgramme, listProgrammeEvents, createProgrammeEvent,
  listBeneficiaries, addBeneficiary, listServices, addService, listOrgUnits,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';

const AGE_BANDS = ['child', 'youth', 'adult', 'senior'];

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.programmes',
  });
  const out = shell.outlet;
  const canEditCatalogue = ctx.modules?.has('settings');

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }), el('p', { text: t('app.loading') }),
  ]));

  let programmes, units;
  try {
    [programmes, units] = await Promise.all([listProgrammes(), listOrgUnits()]);
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
  const picker = el('select', { class: 'select', 'aria-label': t('prog.pick') },
    programmes.map((p) => el('option', { value: p.id,
      text: p.name === p.code ? p.code : `${p.code} — ${p.name}` })));
  const benBtn = el('button', { class: 'btn btn--quiet',
    text: t('prog.beneficiaries'),
    onclick: () => { benCard.hidden = !benCard.hidden; } });
  out.append(el('div', { class: 'toolbar' }, [picker,
    el('span', { class: 'grow' }), benBtn]));

  const benCard = beneficiariesCard();
  benCard.hidden = true;
  const progArea = el('div');
  out.append(benCard, progArea);

  picker.addEventListener('change', () => showProgramme(picker.value));
  if (programmes.length > 0) await showProgramme(programmes[0].id);
  else progArea.append(el('div', { class: 'card state' }, [
    el('h3', { text: t('prog.emptyTitle') })]));
  return shell.teardown;

  /* ---------------- one programme ---------------- */
  async function showProgramme(id) {
    const p = programmes.find((x) => x.id === id);
    clear(progArea);

    const head = el('div', { class: 'card mb-4' });
    head.append(el('div', { class: 'card__head' }, [
      el('h2', { text: p.name === p.code ? p.code : `${p.code} — ${p.name}` }),
      el('span', { class: 'muted',
        text: p.network ?? t('ann.bothNetworks') }),
    ]));
    if (p.description) head.append(el('p', { text: p.description }));

    if (canEditCatalogue) {
      const nameIn = el('input', { class: 'input', value: p.name,
        maxlength: '120', 'aria-label': t('prog.fullName') });
      const descIn = el('input', { class: 'input', value: p.description ?? '',
        maxlength: '2000', placeholder: t('prog.descHint') });
      head.append(el('div', { class: 'row mt-4' }, [
        nameIn, descIn,
        el('button', { class: 'btn btn--quiet', text: t('app.save'),
          onclick: async (e) => {
            e.target.disabled = true;
            try {
              const upd = await updateProgramme(p.id, {
                name: nameIn.value.trim() || p.code,
                description: descIn.value.trim() || null,
              });
              Object.assign(p, upd);
              toast(t('prog.saved'));
              picker.options[picker.selectedIndex].text =
                p.name === p.code ? p.code : `${p.code} — ${p.name}`;
              showProgramme(p.id);
            } catch { toastError(t('errors.save')); }
            finally { e.target.disabled = false; }
          } }),
      ]));
    }
    progArea.append(head);

    /* record an event */
    const title = el('input', { class: 'input', maxlength: '160' });
    const unitSel = el('select', { class: 'select' },
      units.map((u) => el('option', { value: u.id,
        text: `${t(`org.${u.level}`)} — ${u.name}` })));
    const dateIn = el('input', { class: 'input', type: 'date' });
    const locIn = el('input', { class: 'input', maxlength: '300',
      placeholder: t('meet.locationHint') });
    const notesIn = el('textarea', { class: 'input', rows: '2',
      maxlength: '4000' });
    const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
    const submit = el('button', { class: 'btn btn--primary', type: 'submit',
      text: t('prog.recordEvent') });
    const form = el('form', { novalidate: true, class: 'card mb-4',
      onsubmit: async (e) => {
        e.preventDefault();
        if (title.value.trim().length < 3) {
          err.textContent = t('tasks.errTitle'); err.hidden = false; return;
        }
        if (!dateIn.value) {
          err.textContent = t('prog.errDate'); err.hidden = false; return;
        }
        err.hidden = true;
        submit.disabled = true;
        try {
          await createProgrammeEvent({
            programme_id: p.id,
            org_unit_id: unitSel.value,
            title: title.value.trim(),
            event_date: dateIn.value,
            location: locIn.value.trim(),
            notes: notesIn.value.trim(),
          });
          toast(t('prog.eventRecorded'));
          form.reset();
          loadEvents();
        } catch (e2) {
          err.textContent = String(e2?.message ?? '')
            .includes('row-level security')
            ? t('meet.errScope') : t('errors.save');
          err.hidden = false;
        } finally { submit.disabled = false; }
      } }, [
      el('div', { class: 'card__head' }, [
        el('h2', { text: t('prog.newEvent') })]),
      el('div', { class: 'form-grid' }, [
        fieldWrap(t('prog.eventTitle'), title),
        fieldWrap(t('members.orgUnit'), unitSel),
        fieldWrap(t('prog.eventDate'), dateIn),
        fieldWrap(t('meet.location'), locIn),
      ]),
      fieldWrap(t('prog.notes'), notesIn),
      err,
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), submit]),
    ]);
    progArea.append(form);

    const eventsArea = el('div');
    progArea.append(eventsArea);
    await loadEvents();

    async function loadEvents() {
      clear(eventsArea);
      eventsArea.append(el('div', { class: 'state' }, [
        el('div', { class: 'spinner' })]));
      try {
        const { rows, total } = await listProgrammeEvents(p.id);
        clear(eventsArea);
        eventsArea.append(el('h2', { class: 'mb-4',
          text: t('prog.eventsTitle', { n: fmtNumber(total) }) }));
        if (rows.length === 0) {
          eventsArea.append(el('div', { class: 'card state' }, [
            el('h3', { text: t('prog.noEvents') }),
            el('p', { text: t('prog.noEventsHint') }),
          ]));
          return;
        }
        for (const ev of rows) eventsArea.append(eventCard(ev));
      } catch {
        clear(eventsArea);
        eventsArea.append(el('div', { class: 'card state' }, [
          el('h3', { text: t('errors.loadTitle') }),
          el('button', { class: 'btn btn--quiet', text: t('app.retry'),
            onclick: loadEvents }),
        ]));
      }
    }
  }

  /* ---------------- one event + services ---------------- */
  function eventCard(ev) {
    const unitName = units.find((u) => u.id === ev.org_unit_id)?.name ?? '—';
    const card = el('div', { class: 'card mb-4' });
    const head = el('div', { class: 'card__head' });
    head.innerHTML = `
      <div><h3>${esc(ev.title)}</h3>
      <span class="muted">${esc(fmtDate(ev.event_date))} · ${esc(unitName)}
      ${ev.location ? ' · ' + esc(ev.location) : ''}</span></div>`;
    card.append(head);
    if (ev.notes) card.append(el('p', { class: 'muted', text: ev.notes }));

    const svcArea = el('div');
    const openBtn = el('button', { class: 'btn btn--quiet',
      text: t('prog.services'),
      onclick: () => { openBtn.remove(); servicesFlow(ev, svcArea); } });
    card.append(openBtn, svcArea);
    return card;
  }

  async function servicesFlow(ev, area) {
    area.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    let services;
    try { services = await listServices(ev.id); }
    catch {
      area.replaceChildren(el('p', { class: 'field__error',
        text: t('errors.load') }));
      return;
    }
    draw();

    function draw() {
      clear(area);
      area.append(el('h3', { class: 'mb-4 mt-4',
        text: t('prog.servicesCount', { n: fmtNumber(services.length) }) }));
      for (const s of services) {
        area.append(el('p', { class: 'muted' }, [
          el('strong', { text: s.who.full_name }),
          ` (${t(`age.${s.who.age_band}`)}) — ${s.service}` +
          (s.outcome ? ` · ${s.outcome}` : ''),
        ]));
      }

      const search = el('input', { class: 'input', type: 'search',
        placeholder: t('prog.findBeneficiary') });
      const who = el('select', { class: 'select', size: '3' });
      search.addEventListener('input', debounce(async () => {
        try {
          const rows = await listBeneficiaries(search.value.trim());
          clear(who);
          for (const b of rows) {
            who.append(el('option', { value: b.id,
              text: `${b.full_name} (${t(`age.${b.age_band}`)})` }));
          }
          if (rows.length === 0) who.append(el('option', {
            value: '', disabled: true, text: t('prog.noneFound') }));
        } catch { toastError(t('errors.load')); }
      }));
      const svcIn = el('input', { class: 'input', maxlength: '200',
        placeholder: t('prog.serviceHint') });
      const outIn = el('input', { class: 'input', maxlength: '1000',
        placeholder: t('prog.outcomeHint') });
      const addBtn = el('button', { class: 'btn btn--secondary',
        text: t('prog.addService'),
        onclick: async (e) => {
          if (!who.value) { toastError(t('prog.errPick')); return; }
          if (svcIn.value.trim().length < 2) {
            toastError(t('prog.errService')); return;
          }
          e.target.disabled = true;
          try {
            await addService(ev.id, who.value, svcIn.value.trim(),
              outIn.value.trim());
            services = await listServices(ev.id);
            toast(t('prog.serviceAdded'));
            draw();
          } catch (e2) {
            toastError(String(e2?.message ?? '').includes('duplicate')
              ? t('prog.errDuplicate') : t('errors.save'));
            e.target.disabled = false;
          }
        } });
      area.append(
        el('div', { class: 'form-grid mt-4' }, [
          fieldWrap(t('prog.findBeneficiary'), search, who),
          fieldWrap(t('prog.service'), svcIn, outIn),
        ]),
        el('div', { class: 'row' }, [el('span', { class: 'grow' }), addBtn])
      );
    }
  }

  /* ---------------- beneficiaries register ---------------- */
  function beneficiariesCard() {
    const card = el('div', { class: 'card mb-4' });
    card.append(el('div', { class: 'card__head' }, [
      el('h2', { text: t('prog.beneficiaries') })]));
    card.append(el('p', { class: 'muted', text: t('prog.privacyNote') }));

    const nameIn = el('input', { class: 'input', maxlength: '120' });
    const bandSel = el('select', { class: 'select' },
      AGE_BANDS.map((b) => el('option', { value: b, text: t(`age.${b}`) })));
    const unitSel = el('select', { class: 'select' },
      units.map((u) => el('option', { value: u.id,
        text: `${t(`org.${u.level}`)} — ${u.name}` })));
    const notesIn = el('input', { class: 'input', maxlength: '2000',
      placeholder: t('prog.benNotesHint') });
    const addBtn = el('button', { class: 'btn btn--primary',
      text: t('prog.register'),
      onclick: async (e) => {
        if (nameIn.value.trim().length < 2) {
          toastError(t('members.errRequired')); return;
        }
        e.target.disabled = true;
        try {
          await addBeneficiary({
            full_name: nameIn.value.trim(),
            age_band: bandSel.value,
            org_unit_id: unitSel.value,
            notes: notesIn.value.trim(),
          });
          toast(t('prog.registered'));
          nameIn.value = ''; notesIn.value = '';
        } catch (e2) {
          toastError(String(e2?.message ?? '').includes('row-level security')
            ? t('meet.errScope') : t('errors.save'));
        } finally { e.target.disabled = false; }
      } });
    card.append(
      el('div', { class: 'form-grid' }, [
        fieldWrap(t('prog.benName'), nameIn),
        fieldWrap(t('prog.ageBand'), bandSel),
        fieldWrap(t('members.orgUnit'), unitSel),
        fieldWrap(t('prog.notes'), notesIn),
      ]),
      el('div', { class: 'row' }, [el('span', { class: 'grow' }), addBtn])
    );
    return card;
  }
}

function fieldWrap(label, ...controls) {
  return el('div', { class: 'field' }, [
    el('label', { class: 'field__label', text: label }), ...controls,
  ]);
}
