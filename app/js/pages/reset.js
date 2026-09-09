/**
 * WDOS Reset (Phase 74) — sovereign flow: the emailed link carries ?tk=,
 * the token exchanges for a new password through our own database, and
 * no auth-server SMTP is involved anywhere.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { getSession, changePassword, completePasswordReset }
  from '../core/db.js';
import { toast } from '../components/toast.js';

export async function render(root, params) {
  clear(root);
  const wrap = el('div', { class: 'auth' }, [
    el('div', { class: 'auth__brand' }, [
      el('h1', { text: 'WODDI' }),
      el('p', { text: t('app.subtitle') }),
    ]),
  ]);
  root.append(wrap);
  const card = el('div', { class: 'card auth__card' });
  wrap.append(card);

  const tk = params?.tk ? String(params.tk) : null;
  const pw1 = el('input', { class: 'input', type: 'password',
    autocomplete: 'new-password' });
  const pw2 = el('input', { class: 'input', type: 'password',
    autocomplete: 'new-password' });
  const err = el('p', { class: 'field__error', role: 'alert', hidden: true });
  const btn = el('button', { class: 'btn btn--primary',
    style: 'width:100%;', text: t('acct.resetDo') });

  async function submit(fn) {
    err.hidden = true;
    if (pw1.value.length < 8) {
      err.textContent = t('claim.pwShort'); err.hidden = false; return;
    }
    if (pw1.value !== pw2.value) {
      err.textContent = t('claim.pwMismatch'); err.hidden = false; return;
    }
    btn.disabled = true;
    try {
      await fn(pw1.value);
      clear(card);
      card.append(
        el('h2', { text: t('acct.resetDone') }),
        el('p', { class: 'muted', text: t('acct.resetDoneHint') }),
        el('a', { class: 'btn btn--primary mt-4',
          style: 'width:100%;text-align:center;', href: '#/login',
          text: t('auth.signIn') }));
      toast(t('acct.resetDone'));
    } catch (e) {
      err.textContent = e?.message || t('errors.save');
      err.hidden = false; btn.disabled = false;
    }
  }

  const form = (title) => {
    card.append(
      el('h2', { class: 'mb-4', text: title }),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.newPw') }), pw1]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.confirmPw') }),
        pw2]),
      err, btn);
  };

  if (tk) {
    form(t('acct.resetTitle'));
    btn.addEventListener('click',
      () => submit((pw) => completePasswordReset(tk, pw)));
    return;
  }

  const session = await getSession().catch(() => null);
  if (session) {
    form(t('acct.resetTitle'));
    btn.addEventListener('click', () => submit((pw) => changePassword(pw)));
    return;
  }
  // no token in the link, not signed in → paste-the-code path (leg-proof)
  const codeIn = el('input', { class: 'input',
    placeholder: 'e.g. ebef9df1-b190-4204-99e1-8269ea2aa68e',
    style: 'font-size:13px;letter-spacing:.5px;' });
  card.append(
    el('h2', { class: 'mb-4', text: t('acct.resetTitle') }),
    el('p', { class: 'muted', text: t('acct.resetCodeHint') }),
    el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: t('acct.resetCode') }),
      codeIn]));
  form('');
  card.append(el('a', { class: 'auth__alt', href: '#/login',
    text: t('idp.backLogin') }));
  btn.addEventListener('click', () => {
    const raw = codeIn.value.trim();
    const m = raw.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i);
    if (!m) {
      err.textContent = t('acct.resetCodeBad'); err.hidden = false; return;
    }
    submit((pw) => completePasswordReset(m[0], pw));
  });
}
