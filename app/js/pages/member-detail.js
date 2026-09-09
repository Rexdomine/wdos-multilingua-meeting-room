import { el, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import { getMember, updateMember, listOrgUnits, db } from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { journeyCard } from '../components/journey.js';
import { toast, toastError } from '../components/toast.js';

/** Mirror of valid_status_transition() in migration 001 — the database is
 *  authoritative; this map only drives which options the UI offers. */
const NEXT = {
  applicant: ['under_review', 'removed'],
  under_review: ['approved', 'removed'],
  approved: ['activated', 'removed'],
  activated: ['in_training', 'active', 'inactive', 'suspended', 'resigned', 'removed'],
  in_training: ['active', 'inactive', 'suspended', 'resigned', 'removed'],
  active: ['inactive', 'suspended', 'resigned', 'removed', 'alumni'],
  inactive: ['active', 'suspended', 'resigned', 'removed', 'alumni'],
  suspended: ['reinstated', 'removed', 'resigned'],
  resigned: ['reinstated', 'alumni'],
  removed: ['reinstated'],
  alumni: ['reinstated'],
  reinstated: ['active', 'in_training', 'inactive'],
};

const PHONE_RE = /^\+?[0-9 ()-]{7,20}$/;

export async function render(root, params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.members',
  });
  const out = shell.outlet;

  out.append(el('div', { class: 'state' }, [
    el('div', { class: 'spinner' }),
    el('p', { text: t('app.loading') }),
  ]));

  let member, units;
  try {
    [member, units] = await Promise.all([getMember(params.id), listOrgUnits()]);
  } catch {
    clear(out);
    out.append(el('div', { class: 'card state' }, [
      el('h3', { text: t('members.notFoundTitle') }),
      el('p', { text: t('members.notFoundHint') }),
      el('a', { href: '#/members', class: 'btn btn--quiet',
        text: t('members.backToList') }),
    ]));
    return shell.teardown;
  }

  clear(out);
  out.append(el('div', { class: 'row',
    style: 'justify-content:space-between;align-items:center;' }, [
    el('a', { href: '#/members', class: 'muted',
      text: `← ${t('members.backToList')}` }),
    el('a', { href: `#/messages?u=${member.id}`, class: 'btn btn--secondary',
      text: t('members.messageBtn') }),
  ]));

  /* ---- form fields ------------------------------------------------- */
  const first = textField('first_name', t('members.firstName'), member.first_name, true);
  const last = textField('last_name', t('members.lastName'), member.last_name, true);
  const phone = textField('phone', t('members.phone'), member.phone ?? '', false);
  phone.input.type = 'tel';

  const unitSel = el('select', { class: 'select', id: 'org_unit' },
    [el('option', { value: '', text: t('members.noUnit') }),
     ...units.map((u) => el('option', {
       value: u.id, selected: u.id === member.org_unit_id || null,
       text: `${t(`org.${u.level}`)} — ${u.name}`,
     }))]);

  const statusSel = el('select', { class: 'select', id: 'status' },
    [el('option', { value: member.status, selected: true,
       text: t(`status.${member.status}`) }),
     ...(NEXT[member.status] ?? []).map((s) =>
       el('option', { value: s, text: t(`status.${s}`) }))]);

  const reasonField = el('div', { class: 'field', hidden: true }, [
    el('label', { class: 'field__label', for: 'reason',
      text: t('members.changeReason') }),
    el('input', { class: 'input', id: 'reason', maxlength: '300' }),
    el('p', { class: 'field__hint', text: t('members.changeReasonHint') }),
  ]);
  statusSel.addEventListener('change', () => {
    reasonField.hidden = statusSel.value === member.status;
  });

  const save = el('button', { class: 'btn btn--primary', type: 'submit',
    text: t('app.save') });

  const form = el('form', { novalidate: true, class: 'card mt-4', onsubmit: onSave }, [
    el('div', { class: 'card__head' }, [
      el('h2', { text: `${member.first_name} ${member.last_name}` }),
      el('span', { class: 'muted',
        text: member.membership_no
          ? t('members.noLabel', { no: member.membership_no })
          : t('members.noNumberYet') }),
    ]),
    el('div', { class: 'form-grid' }, [
      first.node, last.node, phone.node,
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', for: 'org_unit',
          text: t('members.orgUnit') }), unitSel,
      ]),
      el('div', { class: 'field' }, [
        el('label', { class: 'field__label', for: 'status',
          text: t('members.status') }), statusSel,
      ]),
    ]),
    reasonField,
    el('p', { class: 'muted',
      text: t('members.meta', {
        joined: fmtDate(member.created_at),
        updated: fmtDate(member.updated_at),
      }) }),
    el('div', { class: 'row' }, [el('span', { class: 'grow' }), save]),
  ]);
  out.append(form);
  try {
    const jc = await journeyCard(member.id, 'leader');
    if (jc) out.append(jc);
  } catch { /* optional */ }

  return shell.teardown;

  async function onSave(e) {
    e.preventDefault();
    let ok = true;
    ok = first.check((v) => v.trim().length > 0, t('members.errRequired')) && ok;
    ok = last.check((v) => v.trim().length > 0, t('members.errRequired')) && ok;
    ok = phone.check((v) => !v.trim() || PHONE_RE.test(v.trim()),
      t('members.errPhone')) && ok;
    if (!ok) return;

    const statusChanged = statusSel.value !== member.status;
    save.disabled = true;
    save.textContent = t('app.saving');
    try {
      member = await updateMember(member.id, {
        first_name: first.input.value.trim(),
        last_name: last.input.value.trim(),
        phone: phone.input.value.trim() || null,
        org_unit_id: unitSel.value || null,
      });
      if (statusChanged) {
        // Atomic status change + operator reason in the audit trail
        // (RPC from migration 002; RLS and transition guards apply).
        const reason = reasonField.querySelector('#reason').value.trim();
        const { data, error } = await db().rpc('update_member_status', {
          member_id: member.id,
          new_status: statusSel.value,
          reason: reason || null,
        });
        if (error) throw error;
        member = data;
      }
      toast(t('members.saved'));
      location.hash = '#/members';
    } catch (err) {
      toastError(err?.message?.includes('transition')
        ? t('members.errTransition')
        : t('errors.save'));
    } finally {
      save.disabled = false;
      save.textContent = t('app.save');
    }
  }
}

function textField(id, label, value, required) {
  const err = el('p', { class: 'field__error', hidden: true });
  const input = el('input', { class: 'input', id, value, required: required || null });
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
