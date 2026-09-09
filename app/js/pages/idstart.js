/**
 * WDOS ID Sign-in (Phase 72). For volunteers onboarded from the WODDI
 * Institute form: they type their Volunteer ID (CR101, SRC105, ...),
 * their name appears, they set a password once — and they're inside.
 * No re-registration. Existing signup/sign-in paths are untouched.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { db } from '../core/db.js';
import { toast, toastError } from '../components/toast.js';

export async function render(root) {
  clear(root);
  const card = el('div', { class: 'auth' }, [
    el('div', { class: 'auth__brand' }, [
      el('img', { src: '/assets/woddi-logo.png',
        alt: 'WODDI — The Nurturer',
        style: 'height:84px;max-width:90%;object-fit:contain;' }),
    ]),
  ]);
  root.append(card);

  const box = el('div', { class: 'card auth__card' });
  card.append(box);
  stepId();

  function stepId() {
    clear(box);
    const idIn = el('input', { class: 'input', maxlength: '40',
      placeholder: 'CR101', autocapitalize: 'characters',
      style: 'text-transform:uppercase;letter-spacing:2px;'
        + 'font-size:20px;text-align:center;' });
    const err = el('p', { class: 'field__error', hidden: true });
    const go = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('idp.find') });
    go.addEventListener('click', async () => {
      const v = idIn.value.trim().toUpperCase();
      if (!v) return;
      go.disabled = true; err.hidden = true;
      try {
        const { data, error } = await db().rpc('id_lookup', { idno: v });
        if (error) throw error;
        const hit = data?.[0];
        if (!hit) {
          err.textContent = t('idp.notFound'); err.hidden = false;
        } else if (hit.claimed) {
          stepClaimed(hit);
        } else {
          stepPassword(v, hit);
        }
      } catch (e) {
        err.textContent = e?.message || t('errors.load'); err.hidden = false;
      }
      go.disabled = false;
    });
    idIn.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') go.click();
    });
    box.append(
      el('h2', { text: t('idp.title') }),
      el('p', { class: 'muted', text: t('idp.hint') }),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('idp.label') }), idIn,
      ]),
      err, go,
      el('a', { class: 'auth__alt', href: '#/login',
        text: t('idp.backLogin') }),
    );
    idIn.focus();
  }

  function stepClaimed(hit) {
    clear(box);
    const pw = el('input', { class: 'input', type: 'password',
      autocomplete: 'current-password' });
    const err = el('p', { class: 'field__error', hidden: true });
    const go = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('idp.signInNow') });
    go.addEventListener('click', async () => {
      err.hidden = true; go.disabled = true;
      try {
        const { error } = await db().auth.signInWithPassword({
          email: hit.email, password: pw.value });
        if (error) throw error;
        toast(t('idp.inside', { name: hit.first_name }));
        location.hash = '#/me';
        location.reload();
      } catch (e) {
        err.textContent = /invalid/i.test(String(e?.message))
          ? t('idp.wrongPw') : (e?.message || t('errors.save'));
        err.hidden = false; go.disabled = false;
      }
    });
    pw.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') go.click(); });
    box.append(
      el('h2', { text: t('idp.welcomeBack',
        { name: `${hit.first_name} ${hit.last_name}` }) }),
      el('p', { class: 'muted',
        text: t('idp.pwOnly', { email: hit.email_hint }) }),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.pw') }), pw,
      ]),
      err, go,
      el('a', { class: 'auth__alt', href: '#/reset',
        text: t('idp.forgot') }),
      el('button', { class: 'btn btn--quiet', style: 'width:100%;',
        text: t('idp.notMe'), onclick: stepId }),
    );
    pw.focus();
  }

  function stepPassword(idno, hit) {
    clear(box);
    const pw1 = el('input', { class: 'input', type: 'password',
      autocomplete: 'new-password' });
    const pw2 = el('input', { class: 'input', type: 'password',
      autocomplete: 'new-password' });
    const err = el('p', { class: 'field__error', hidden: true });
    const go = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('idp.enter') });
    go.addEventListener('click', async () => {
      err.hidden = true;
      if (pw1.value.length < 8) {
        err.textContent = t('claim.pwShort'); err.hidden = false; return;
      }
      if (pw1.value !== pw2.value) {
        err.textContent = t('claim.pwMismatch'); err.hidden = false; return;
      }
      go.disabled = true;
      try {
        const { error: suErr } = await db().auth.signUp({
          email: hit.email, password: pw1.value,
          options: { data: {
            first_name: hit.first_name, last_name: hit.last_name } },
        });
        if (suErr && !/already/i.test(suErr.message)) throw suErr;
        const { error: siErr } = await db().auth.signInWithPassword({
          email: hit.email, password: pw1.value });
        if (siErr) throw siErr;
        toast(t('idp.inside', { name: hit.first_name }));
        location.hash = '#/me';
        location.reload();
      } catch (e) {
        const m = String(e?.message || '');
        err.textContent = (m === '{}' || /confirmation|smtp|sending/i.test(m)
          || Number(e?.status) >= 500)
          ? t('claim.errSmtp') : (m || t('errors.save'));
        err.hidden = false; go.disabled = false;
      }
    });
    box.append(
      el('h2', { text: t('idp.hello',
        { name: `${hit.first_name} ${hit.last_name}` }) }),
      el('p', { class: 'muted', text: t('idp.confirm',
        { id: idno, email: hit.email_hint }) }),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('claim.pw1') }), pw1,
      ]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('claim.pw2') }), pw2,
      ]),
      err, go,
      el('button', { class: 'btn btn--quiet', style: 'width:100%;',
        text: t('idp.notMe'), onclick: stepId }),
    );
  }
}
