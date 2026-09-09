/**
 * WODDI Volunteer Registration — Phase 52. Public, simple, open-ended.
 * Lives inside WDOS (no external bridge to break). On submit the instant-
 * approval trigger fires; the success screen immediately offers "Create
 * your login" and tells them a welcome email is on its way — registration
 * to activation journey in one sitting.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { db } from '../core/db.js';

export async function render(root) {
  clear(root);
  const inner = el('div', { class: 'card' });
  root.append(el('div', { class: 'auth' }, [
    el('div', { class: 'auth__card', style: 'max-width:560px;' }, [
      el('div', { class: 'auth__brand' }, [
        el('strong', { text: 'WODDI' }),
        el('span', { text: t('vol.subtitle') }),
      ]),
      inner,
    ]),
  ]));
  form();

  function field(labelText, input, hint) {
    const w = el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: labelText }), input]);
    if (hint) w.append(el('p', { class: 'muted',
      style: 'font-size:12px;margin-top:2px;', text: hint }));
    return w;
  }

  function form() {
    clear(inner);
    inner.append(
      el('h2', { style: 'margin-bottom:4px;', text: t('vol.title') }),
      el('p', { class: 'muted mb-4', text: t('vol.hint') }));

    const name = el('input', { class: 'input', autocomplete: 'name',
      placeholder: t('vol.namePh') });
    const email = el('input', { class: 'input', type: 'email',
      autocomplete: 'email', placeholder: 'you@example.com' });
    const phone = el('input', { class: 'input', type: 'tel',
      autocomplete: 'tel', placeholder: '+234 …' });
    // The Founder's rule: your age decides your network.
    // 18 to 29 -> WNNN (Nurture NextGen), 30 and above -> WGMN (Good Mother).
    const age = el('select', { class: 'select' }, [
      el('option', { value: '', text: t('vol.agePick') }),
      el('option', { value: '18-29', text: t('vol.age1829') }),
      el('option', { value: '30+', text: t('vol.age30') }),
    ]);
    const netNote = el('p', { class: 'muted', hidden: true,
      style: 'margin:4px 0 0;' });
    const network = { get value() {
      return age.value === '18-29' ? 'WNNN'
        : age.value === '30+' ? 'WGMN' : '';
    } };
    age.addEventListener('change', () => {
      netNote.hidden = !network.value;
      netNote.textContent = network.value === 'WNNN'
        ? t('vol.netWnnn') : t('vol.netWgmn');
    });
    const country = el('input', { class: 'input',
      placeholder: t('vol.countryPh') });
    const about = el('textarea', { class: 'input', rows: '5',
      placeholder: t('vol.aboutPh') });
    const err = el('p', { class: 'field__error', hidden: true });
    const btn = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('vol.submit') });

    inner.append(
      field(t('vol.name'), name),
      field(t('vol.email'), email, t('vol.emailHint')),
      field(t('vol.phone'), phone),
      field(t('vol.age'), age), netNote,
      field(t('vol.country'), country),
      field(t('vol.about'), about, t('vol.aboutHint')),
      err, btn);

    btn.addEventListener('click', async () => {
      err.hidden = true;
      const nm = name.value.trim();
      const em = email.value.trim().toLowerCase();
      if (nm.length < 3) { show(t('vol.errName')); return; }
      if (!em.includes('@')) { show(t('vol.errEmail')); return; }
      if (about.value.trim().length < 10) { show(t('vol.errAbout')); return; }
      btn.disabled = true;
      try {
        if (!network.value) {
          show(t('vol.agePick')); return;
        }
        const { submitVolunteerReg } = await import('../core/db.js');
        const filed = await submitVolunteerReg({
          fullName: nm, email: em,
          phone: phone.value.trim(), network: network.value,
          country: country.value.trim(), about: about.value.trim(),
        });
        try { const { attachStoredReferral } = await import('../core/db.js'); await attachStoredReferral(em); } catch { /* best effort */ }
        success(nm.split(' ')[0], em, filed);
      } catch (e) {
        show(String(e?.message || '').includes('duplicate')
          ? t('vol.errDup') : t('vol.errSave'));
        btn.disabled = false;
      }
    });

    function show(m) { err.textContent = m; err.hidden = false; }
  }

  function success(firstName, em, filed) {
    clear(inner);
    inner.append(
      el('h2', { style: 'color:var(--lime,#7CB518);margin-bottom:6px;',
        text: t('vol.approvedTitle', { name: firstName }) }),
      el('p', { style: 'line-height:1.6;', text: t('vol.approvedBody') }),
      el('p', { style: 'font-weight:700;', text: t('vol.doneRef', {
        ref: filed?.ref || '', network: filed?.network || '' }) }),
      el('p', { class: 'muted mt-2', text: t('vol.emailNote', { email: em }) }),
      el('a', { class: 'btn btn--primary mt-4',
        style: 'width:100%;text-align:center;display:block;', href: '#/claim',
        text: t('vol.claimNow') }),
      el('p', { class: 'muted mt-4', style: 'font-size:12px;',
        text: t('vol.sameEmail') }));
  }
}
