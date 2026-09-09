import { el, clear } from '../core/dom.js';
import { t, getLocale } from '../core/i18n.js';
import { listOrgUnits, submitApplication, listCountryLevelNames }
  from '../core/db.js';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE_RE = /^\+?[0-9 ()-]{7,20}$/;

export async function render(root) {
  clear(root);
  const wrap = el('div', { class: 'auth' });
  const card = el('div', { class: 'auth__card', style: 'width:min(560px,100%);' });
  wrap.append(card);
  root.append(wrap);

  card.append(
    el('div', { class: 'auth__brand' }, [
      el('strong', { text: 'WODDI' }),
      el('span', { text: t('apply.subtitle') }),
    ]),
    el('div', { class: 'card state' }, [
      el('div', { class: 'spinner' }),
      el('p', { text: t('app.loading') }),
    ])
  );

  let units, levelNames;
  try {
    [units, levelNames] = await Promise.all([
      listOrgUnits(), listCountryLevelNames()]);
  } catch {
    card.lastChild.replaceWith(el('div', { class: 'card state' }, [
      el('h3', { text: t('errors.loadTitle') }),
      el('p', { text: t('errors.loadHint') }),
      el('button', { class: 'btn btn--quiet', text: t('app.retry'),
        onclick: () => render(root) }),
    ]));
    return;
  }

  const countries = units.filter((u) => u.level === 'country')
    .sort((a, b) => a.name.localeCompare(b.name));
  if (countries.length === 0) {
    card.lastChild.replaceWith(el('div', { class: 'card state' }, [
      el('h3', { text: t('apply.noChaptersTitle') }),
      el('p', { text: t('apply.noChaptersHint') }),
    ]));
    return;
  }
  const childrenOf = (pid) => units
    .filter((u) => u.parent_id === pid)
    .sort((a, b) => a.name.localeCompare(b.name));

  const f = {
    first: field('first_name', t('members.firstName')),
    last: field('last_name', t('members.lastName')),
    email: field('email', t('auth.email'), 'email'),
    phone: field('phone', t('apply.phoneOptional'), 'tel'),
  };
  // The Founder's rule: age decides the network.
  const network = select('network', t('apply.age'),
    [['', t('vol.agePick')],
     ['WNNN', t('vol.age1829')], ['WGMN', t('vol.age30')]]);
  /* Cascading place picker: country -> local levels -> chapter.
     The deepest chosen unit becomes the application's home. */
  let placeChoice = null;
  const placeWrap = el('div');
  function levelLabel(countryId, depth) {
    const names = levelNames.get(countryId) ?? {};
    if (depth === 1) return names.state_region ?? t('org.state_region');
    if (depth === 2) return names.district_lga ?? t('org.district_lga');
    return t('org.chapter');
  }
  function buildLevel(parent, countryId, depth) {
    const kids = childrenOf(parent.id);
    if (kids.length === 0) return;
    const label = depth === 0 ? t('org.country')
      : levelLabel(countryId, depth);
    const sel = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('apply.pickLevel', { level: label }) }),
      ...kids.map((u) => el('option', { value: u.id, text: u.name })),
    ]);
    const holder = el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: label }), sel]);
    sel.addEventListener('change', () => {
      while (holder.nextSibling) holder.nextSibling.remove();
      const chosen = units.find((u) => u.id === sel.value);
      if (!chosen) { placeChoice = null; return; }
      placeChoice = chosen;
      buildLevel(chosen, depth === 0 ? chosen.id : countryId, depth + 1);
    });
    placeWrap.append(holder);
  }
  (function buildCountry() {
    const sel = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('apply.pickLevel',
        { level: t('org.country') }) }),
      ...countries.map((u) => el('option', { value: u.id, text: u.name })),
    ]);
    const holder = el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: t('org.country') }), sel]);
    sel.addEventListener('change', () => {
      while (holder.nextSibling) holder.nextSibling.remove();
      const chosen = units.find((u) => u.id === sel.value);
      if (!chosen) { placeChoice = null; return; }
      placeChoice = chosen;
      buildLevel(chosen, chosen.id, 1);
    });
    placeWrap.append(holder);
  })();

  const motivation = el('textarea', {
    class: 'input', id: 'motivation', rows: '5', maxlength: '2000',
  });
  const motivationErr = el('p', { class: 'field__error', hidden: true });
  const formErr = el('p', { class: 'field__error', role: 'alert', hidden: true });
  const submit = el('button', { class: 'btn btn--primary', type: 'submit',
    style: 'width:100%;', text: t('apply.submit') });

  const form = el('form', { novalidate: true, class: 'card', onsubmit: onSubmit }, [
    el('div', { class: 'form-grid' }, [f.first.node, f.last.node, f.email.node, f.phone.node]),
    network.node, placeWrap,
    el('div', { class: 'field' }, [
      el('label', { class: 'field__label', for: 'motivation', text: t('apply.motivation') }),
      motivation,
      el('p', { class: 'field__hint', text: t('apply.motivationHint') }),
      motivationErr,
    ]),
    formErr, submit,
    el('p', { class: 'muted mt-4', style: 'text-align:center;' }, [
      el('a', { href: '#/login', text: t('apply.haveAccount') }),
    ]),
  ]);
  card.lastChild.replaceWith(form);

  async function onSubmit(e) {
    e.preventDefault();
    let ok = true;
    ok = f.first.check((v) => v.trim().length > 0, t('members.errRequired')) && ok;
    ok = f.last.check((v) => v.trim().length > 0, t('members.errRequired')) && ok;
    ok = f.email.check((v) => EMAIL_RE.test(v.trim()), t('auth.errEmail')) && ok;
    ok = f.phone.check((v) => !v.trim() || PHONE_RE.test(v.trim()),
      t('members.errPhone')) && ok;
    const mBad = motivation.value.trim().length < 20;
    motivation.setAttribute('aria-invalid', String(mBad));
    motivationErr.textContent = mBad ? t('apply.errMotivation') : '';
    motivationErr.hidden = !mBad;
    ok = !mBad && ok;
    if (!ok) return;

    formErr.hidden = true;
    submit.disabled = true;
    submit.textContent = t('apply.submitting');
    try {
      const refEmail = f.email.input.value.trim();
      await submitApplication({
        first_name: f.first.input.value.trim(),
        last_name: f.last.input.value.trim(),
        email: refEmail,
        phone: f.phone.input.value.trim(),
        network: network.input.value,
        org_unit_id: placeChoice?.id,
        motivation: motivation.value.trim(),
        preferred_locale: getLocale(),
      });
      try { const { attachStoredReferral } = await import('../core/db.js'); await attachStoredReferral(refEmail); } catch { /* best effort */ }
      card.replaceChildren(el('div', { class: 'card state' }, [
        el('h3', { text: t('apply.doneTitle') }),
        el('p', { text: t('apply.doneHint') }),
        el('a', { class: 'btn btn--primary mt-4',
          style: 'display:inline-block;', href: '#/login',
          text: t('apply.doneCta') }),
      ]));
    } catch (err) {
      const msg = String(err?.message ?? '');
      formErr.textContent =
        msg.includes('applications_live_email_uq') ? t('apply.errDuplicate')
        : msg.includes('profile with this email') ? t('apply.errExisting')
        : t('errors.network');
      formErr.hidden = false;
    } finally {
      submit.disabled = false;
      submit.textContent = t('apply.submit');
    }
  }
}

function field(id, label, type = 'text') {
  const err = el('p', { class: 'field__error', hidden: true });
  const input = el('input', { class: 'input', id, type });
  const node = el('div', { class: 'field' }, [
    el('label', { class: 'field__label', for: id, text: label }), input, err,
  ]);
  return {
    node, input,
    check(fn, message) {
      const bad = !fn(input.value);
      input.setAttribute('aria-invalid', String(bad));
      err.textContent = bad ? message : '';
      err.hidden = !bad;
      return !bad;
    },
  };
}

function select(id, label, options) {
  const input = el('select', { class: 'select', id },
    options.map(([v, text]) => el('option', { value: v, text })));
  const node = el('div', { class: 'field' }, [
    el('label', { class: 'field__label', for: id, text: label }), input,
  ]);
  return { node, input };
}
