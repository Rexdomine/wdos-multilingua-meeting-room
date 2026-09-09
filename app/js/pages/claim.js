/**
 * Phase 44 — Claim your account. Approved applicants create their own
 * login: WDOS confirms an approved application exists for the email, the
 * person chooses a password, and signup enriches the profile from the
 * application and starts the activation journey automatically.
 */
import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { claimCheck, claimSignUp } from '../core/db.js';

export async function render(root) {
  clear(root);
  const inner = el('div', { class: 'card' });
  root.append(el('div', { class: 'auth' }, [
    el('div', { class: 'auth__card' }, [
      el('div', { class: 'auth__brand' }, [
        el('strong', { text: 'WODDI' }),
        el('span', { text: t('app.subtitle') }),
      ]),
      inner,
    ]),
  ]));
  const card = inner;
  step1();

  function head(sub) {
    return [
      el('h2', { style: 'margin-bottom:6px;', text: t('claim.title') }),
      sub ? el('p', { class: 'muted', text: sub }) : null,
    ];
  }


  function googleBits() {
      const gBtn = el('button', {
        type: 'button', style: 'margin-top:8px;width:100%;display:flex;align-items:center;justify-content:center;gap:10px;background:#fff;color:#3c4043;border:1px solid #dadce0;border-radius:8px;padding:11px 16px;font-size:15px;font-weight:600;cursor:pointer;' });
      gBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615z"/><path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"/><path fill="#FBBC05" d="M3.964 10.71A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.007-2.332z"/><path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"/></svg>' + '<span></span>';
      gBtn.lastChild.textContent = t('auth.google');
      gBtn.addEventListener('click', async () => {
        const { signInWithGoogle } = await import('../core/db.js');
        try { await signInWithGoogle(); } catch { /* not configured */ }
      });
      const gHint = el('p', { class: 'muted', style: 'font-size:12px;',
        text: t('claim.googleHint') });
    return [gBtn, gHint];
  }

  function step1() {
    clear(card);
    const email = el('input', { class: 'input', type: 'email',
      placeholder: t('claim.emailPh'), autocomplete: 'email' });
    const err = el('p', { class: 'field__error', hidden: true });
    const act = el('div', { hidden: true, style: 'margin-top:8px;' });
    const btn = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('claim.check') });
    btn.addEventListener('click', async () => {
      err.hidden = true; btn.disabled = true;
      try {
        act.hidden = true; act.replaceChildren();
        const r = await claimCheck(email.value.trim());
        if (r.eligible) { step2(email.value.trim(), r.first_name); return; }
        err.textContent = t(`claim.err.${r.reason}`);
        err.hidden = false;
        const ACTIONS = {
          use_volunteer_id: { href: '#/id', label: t('claim.act.useId') },
          not_found:        { href: '#/id', label: t('claim.act.useId') },
          has_account:      { href: '#/login', label: t('claim.act.signIn') },
        };
        const a = ACTIONS[r.reason];
        if (a) {
          act.append(el('a', { href: a.href,
            class: 'btn btn--primary',
            style: 'width:100%;text-align:center;', text: a.label }));
          act.hidden = false;
        }
      } catch { err.textContent = t('errors.load'); err.hidden = false; }
      finally { btn.disabled = false; }
    });
    card.append(...head(t('claim.hint')), el('div', { class: 'field' }, [
      el('label', { class: 'field__label', text: t('claim.email') }), email]),
      err, act, btn, ...googleBits(),
      el('p', { class: 'muted mt-4', style: 'text-align:center;' }, [
        el('a', { href: '#/login', text: t('claim.backToLogin') })]));
  }

  function step2(email, firstName) {
    clear(card);
    const pw1 = el('input', { class: 'input', type: 'password',
      autocomplete: 'new-password' });
    const pw2 = el('input', { class: 'input', type: 'password',
      autocomplete: 'new-password' });
    const err = el('p', { class: 'field__error', hidden: true });
    const act = el('div', { hidden: true, style: 'margin-top:8px;' });
    const btn = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('claim.create') });
    const [gBtn, gHint] = googleBits();
    btn.addEventListener('click', async () => {
      err.hidden = true;
      if (pw1.value.length < 8) { err.textContent = t('acct.errShort'); err.hidden = false; return; }
      if (pw1.value !== pw2.value) { err.textContent = t('acct.errMatch'); err.hidden = false; return; }
      btn.disabled = true;
      try {
        const data = await claimSignUp(email, pw1.value);
        clear(card);
        card.append(...head(null),
          el('p', { class: 'q-feedback q-feedback--ok',
            text: t('claim.welcome', { name: firstName || '' }) }),
          el('p', { class: 'muted', text: data.session
            ? t('claim.doneNow') : t('claim.doneConfirm') }),
          el('a', { class: 'btn btn--primary mt-4',
            style: 'width:100%;text-align:center;', href: '#/login',
            text: t('claim.goLogin') }));
      } catch (e) {
        const msg = String(e?.message || '');
        const smtpish = msg === '{}' || /confirmation|smtp|sending/i.test(msg)
          || Number(e?.status) >= 500;
        err.textContent = msg.includes('already registered')
          ? t('claim.err.has_account')
          : smtpish ? t('claim.errSmtp')
          : msg ? t('claim.errWith', { msg }) : t('errors.save');
        err.hidden = false; btn.disabled = false;
      }
    });
    card.append(...head(t('claim.helloSet', { name: firstName || '' })),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.newPw') }), pw1]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', text: t('acct.confirmPw') }), pw2]),
      err, btn);
  }
}
