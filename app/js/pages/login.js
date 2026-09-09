import { el, clear } from '../core/dom.js';
import { t } from '../core/i18n.js';
import { signIn, requestPasswordReset } from '../core/db.js';
import { toast } from '../components/toast.js';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export async function render(root, params = {}) {
  clear(root);

  const emailErr = el('p', { class: 'field__error', id: 'email-err', hidden: true });
  const passErr = el('p', { class: 'field__error', id: 'pass-err', hidden: true });
  const formErr = el('p', { class: 'field__error', role: 'alert', hidden: true });
  if (params.oauth === 'failed') {
    formErr.textContent = t('auth.errGoogle');
    formErr.hidden = false;
  }
  // v67.1 diagnostics: if the session ended without a Sign out click in the
  // last 10 minutes, say so with the time, page and build, and clear the mark.
  try {
    const last = JSON.parse(localStorage.getItem('wdos.lastAutoSignOut') || 'null');
    if (last && Date.now() - new Date(last.at).getTime() < 10 * 60 * 1000) {
      formErr.textContent = t('auth.autoSignedOut', { at: new Date(last.at).toLocaleTimeString(), page: last.page || '', build: last.build || '' });
      formErr.hidden = false;
      localStorage.removeItem('wdos.lastAutoSignOut');
    }
  } catch { /* ok */ }

  const email = el('input', {
    class: 'input', type: 'email', id: 'email', autocomplete: 'username',
    required: true, 'aria-describedby': 'email-err',
  });
  const password = el('input', {
    class: 'input', type: 'password', id: 'password',
    autocomplete: 'current-password', required: true,
    'aria-describedby': 'pass-err',
  });
  const submit = el('button', {
    class: 'btn btn--primary', type: 'submit',
    style: 'width:100%;', text: t('auth.signIn'),
  });
  const googleBtn = el('button', {
    type: 'button', style: 'margin-top:10px;width:100%;display:flex;align-items:center;justify-content:center;gap:10px;background:#fff;color:#3c4043;border:1px solid #dadce0;border-radius:8px;padding:11px 16px;font-size:15px;font-weight:600;cursor:pointer;' });
  googleBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.716v2.259h2.908c1.702-1.567 2.684-3.875 2.684-6.615z"/><path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"/><path fill="#FBBC05" d="M3.964 10.71A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.007-2.332z"/><path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"/></svg>'
    + '<span></span>';
  googleBtn.lastChild.textContent = t('auth.google');
  googleBtn.addEventListener('click', async () => {
    const { signInWithGoogle } = await import('../core/db.js');
    formErr.hidden = true;
    try { await signInWithGoogle(); }
    catch (err) {
      formErr.textContent = t('auth.errGoogle');
      formErr.hidden = false;
    }
  });

  const form = el('form', { novalidate: true, onsubmit: onSubmit }, [
    el('div', { class: 'field' }, [
      el('label', { class: 'field__label', for: 'email', text: t('auth.email') }),
      email, emailErr,
    ]),
    el('div', { class: 'field' }, [
      el('label', { class: 'field__label', for: 'password', text: t('auth.password') }),
      password, passErr,
    ]),
    formErr,
    submit,
  ]);

    const forgotBtn = el('button', {
    class: 'btn btn--quiet', type: 'button', text: t('auth.forgot'),
    onclick: () => { forgotBox.hidden = !forgotBox.hidden; } });
  const fEmail = el('input', { class: 'input', type: 'email',
    autocomplete: 'email', placeholder: t('auth.email') });
  const forgotBox = el('div', { class: 'card mt-4', hidden: true }, [
    el('p', { class: 'muted', text: t('auth.forgotHint') }),
    el('div', { class: 'field' }, [fEmail]),
    el('div', { class: 'row' }, [
      el('span', { class: 'grow' }),
      el('button', { class: 'btn btn--secondary', text: t('auth.sendReset'),
        onclick: async (e) => {
          if (!fEmail.value.trim()) return;
          e.target.disabled = true;
          try {
            await requestPasswordReset(fEmail.value.trim());
          } catch { /* neutral response either way */ }
          toast(t('auth.resetSent'));
          e.target.disabled = false;
          forgotBox.hidden = true;
        } }),
    ]),
  ]);
root.append(
    el('div', { class: 'auth' }, [
      el('div', { class: 'auth__card' }, [
        el('div', { class: 'auth__brand' }, [
          el('img', { src: '/assets/woddi-logo.png',
            alt: 'WODDI — The Nurturer',
            style: 'height:74px;max-width:88%;object-fit:contain;' }),
        ]),
        el('div', { class: 'card' }, [form, googleBtn]),
        el('div', { class: 'mt-4', style:
          'display:flex;gap:16px;justify-content:center;flex-wrap:wrap;' }, [
          forgotBtn,
          el('a', { href: '#/reset', class: 'muted',
            style: 'font-size:13px;align-self:center;',
            text: t('login.haveCode') }),
        ]),
        forgotBox,
        el('div', { class: 'muted', style:
          'display:flex;align-items:center;gap:12px;margin:18px 0 10px;' }, [
          el('span', { style: 'flex:1;height:1px;background:var(--line,#e5e5e5);' }),
          el('span', { style: 'font-size:12px;letter-spacing:1px;'
            + 'text-transform:uppercase;', text: t('login.newHere') }),
          el('span', { style: 'flex:1;height:1px;background:var(--line,#e5e5e5);' }),
        ]),
        el('div', { style: 'display:flex;flex-direction:column;gap:10px;' }, [
          el('a', { href: '#/id', class: 'btn btn--primary',
            style: 'width:100%;text-align:center;',
            text: t('login.ctaId') }),
          el('a', { href: '#/claim', class: 'btn btn--secondary',
            style: 'width:100%;text-align:center;',
            text: t('login.ctaClaim') }),
          el('a', { href: '#/volunteer', class: 'btn btn--secondary',
            style: 'width:100%;text-align:center;',
            text: t('login.ctaVol') }),
          el('a', { href: '#/apply', class: 'btn btn--quiet',
            style: 'width:100%;text-align:center;',
            text: t('login.ctaApply') }),
        ]),
      ]),
    ])
  );
  email.focus();

  async function onSubmit(e) {
    e.preventDefault();
    let ok = true;
    ok = validate(email, emailErr,
      EMAIL_RE.test(email.value.trim()) ? '' : t('auth.errEmail')) && ok;
    ok = validate(password, passErr,
      password.value.length >= 8 ? '' : t('auth.errPassword')) && ok;
    if (!ok) return;

    formErr.hidden = true;
    submit.disabled = true;
    submit.textContent = t('auth.signingIn');
    try {
      await signIn(email.value.trim(), password.value);
      location.hash = '#/';
    } catch (err) {
      const m = String(err?.message ?? '');
      formErr.textContent =
        m === 'Invalid login credentials' ? t('auth.errCredentials')
        : m.includes('not confirmed') ? t('auth.errUnconfirmed')
        : m.includes('security purposes') ? t('auth.errRateLimit')
        : t('errors.network');
      formErr.hidden = false;
    } finally {
      submit.disabled = false;
      submit.textContent = t('auth.signIn');
    }
  }
}

function validate(input, errNode, message) {
  const bad = Boolean(message);
  input.setAttribute('aria-invalid', String(bad));
  errNode.textContent = message;
  errNode.hidden = !bad;
  return !bad;
}
