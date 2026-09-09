/**
 * WDOS courses — Phase 37. Lives inside the mobile Learn tab (works on
 * desktop too). Flow: course list → module list (locked until the previous
 * module is passed — the database enforces it) → lesson + 3-question check
 * (pass = at most one wrong, retakes allowed) → numbered certificate,
 * downloadable as a PNG image or printed to PDF.
 */
import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import {
  listCourses, getCourseModules, getModuleQuestions,
  getMyEnrollments, getMyModulePasses, enrollCourse, submitCourseModule,
} from '../core/db.js';
import { toast, toastError } from './toast.js';

export async function renderCourses(container, profile, refreshOuter) {
  const state = { courses: null, enrollments: null };

  await list();

  async function list() {
    clear(container);
    container.append(el('div', { class: 'state' }, [el('div', { class: 'spinner' })]));
    try {
      [state.courses, state.enrollments] = await Promise.all([
        listCourses(), getMyEnrollments(),
      ]);
    } catch {
      clear(container);
      container.append(el('p', { class: 'muted', text: t('course.needsMigration') }));
      return;
    }
    clear(container);
    if (!state.courses.length) {
      container.append(el('p', { class: 'muted', text: t('course.none') }));
      return;
    }
    for (const c of state.courses) {
      const enr = state.enrollments.find((e) => e.course_id === c.id);
      const card = el('div', { class: 'card', style: 'margin-bottom:12px;' });
      card.append(
        el('div', { class: 'notice__kind', text: t('course.course') }),
        el('h3', { style: 'margin:2px 0 6px;', text: c.title }),
        el('p', { class: 'muted', style: 'font-size:13px;', text: c.description }),
      );
      const row = el('div', { class: 'row mt-2', style: 'gap:8px;flex-wrap:wrap;' });
      if (enr?.completed_at) {
        row.append(
          el('span', { class: 'badge badge--active', text: t('course.completed') }),
          el('button', { class: 'btn btn--primary', text: t('course.viewCert'),
            onclick: () => certificate(c, enr) }));
      } else if (enr) {
        row.append(el('button', { class: 'btn btn--primary',
          text: t('course.continue'), onclick: () => modules(c, enr) }));
      } else {
        row.append(el('button', { class: 'btn btn--secondary',
          text: t('course.enroll'),
          onclick: async (e) => {
            e.target.disabled = true;
            try {
              const eid = await enrollCourse(c.id);
              const enr2 = { id: eid, course_id: c.id, completed_at: null };
              state.enrollments.push(enr2);
              modules(c, enr2);
            } catch (err) {
              toastError(err?.message || t('errors.save'));
              e.target.disabled = false;
            }
          } }));
      }
      card.append(row);
      container.append(card);
    }
  }

  async function modules(course, enr) {
    clear(container);
    container.append(back(list));
    container.append(el('div', { class: 'learn-card learn-card--class' }, [
      el('small', { text: t('course.course') }),
      el('h3', { text: course.title }),
    ]));
    let mods, passes;
    try {
      [mods, passes] = await Promise.all([
        getCourseModules(course.id), getMyModulePasses(enr.id),
      ]);
    } catch { container.append(errP()); return; }
    const passMap = new Map(passes.map((p) => [p.module_id, p]));
    let unlocked = true;                       // module 1 always open
    for (const m of mods) {
      const p = passMap.get(m.id);
      const done = p?.passed;
      const open = unlocked;
      const cls = 'day-row' + (done ? ' day-row--done' : '');
      container.append(el('button', {
        class: cls, disabled: !open || null,
        onclick: () => moduleView(course, enr, mods, m, passMap),
      }, [
        el('div', { class: 'day-row__n', text: done ? '\u2713' : String(m.seq) }),
        el('div', { class: 'day-row__t' }, [
          el('b', { text: m.title }),
          el('span', { text: done
            ? t('course.passedScore', { s: p.score, tt: p.total })
            : open ? t('course.openModule') : t('course.locked') }),
        ]),
      ]));
      unlocked = !!done;                       // next opens only after a pass
    }
    if (enr.completed_at) {
      container.append(el('button', { class: 'btn btn--primary mt-2',
        style: 'width:100%;', text: t('course.viewCert'),
        onclick: () => certificate(course, enr) }));
    }
  }

  async function moduleView(course, enr, mods, m, passMap) {
    clear(container);
    container.append(back(() => modules(course, enr)));
    container.append(el('div', { class: 'learn-card learn-card--class' }, [
      el('small', { text: t('course.moduleN', { n: m.seq }) }),
      el('h3', { text: m.title }),
    ]));
    const lesson = el('div', { class: 'card',
      style: 'line-height:1.65;white-space:pre-wrap;' });
    lesson.textContent = m.lesson;
    container.append(lesson);

    const already = passMap.get(m.id);
    if (already?.passed) {
      container.append(el('p', { class: 'q-feedback q-feedback--ok mt-2',
        text: t('course.passedScore', { s: already.score, tt: already.total }) }));
      return;
    }

    let qs;
    try { qs = await getModuleQuestions(m.id); }
    catch { container.append(errP()); return; }

    container.append(el('h3', { class: 'mt-4 mb-2', text: t('course.check') }));
    const chosen = {};   // question_id -> letter
    const qCards = qs.map((qq) => {
      const card = el('div', { class: 'q-item' });
      card.append(el('div', { class: 'q-item__p', text: qq.prompt }));
      const opts = qq.options.map((label) => {
        const key = label.split('.')[0].trim();
        const b = el('button', { class: 'opt', 'data-key': key }, [
          el('span', { class: 'opt__box' }), el('span', { text: label }),
        ]);
        b.addEventListener('click', () => {
          chosen[qq.id] = key;
          card.querySelectorAll('.opt').forEach((o) =>
            o.setAttribute('aria-pressed', String(o === b)));
        });
        return b;
      });
      opts.forEach((o) => card.append(o));
      card.dataset.qid = qq.id;
      return card;
    });
    qCards.forEach((c2) => container.append(c2));

    const fb = el('p', { class: 'q-feedback' });
    const submit = el('button', { class: 'btn btn--primary',
      style: 'width:100%;', text: t('me.submit') });
    submit.addEventListener('click', async () => {
      if (Object.keys(chosen).length < qs.length) {
        toastError(t('course.answerAll')); return;
      }
      submit.disabled = true;
      let res;
      try { res = await submitCourseModule(enr.id, m.id, chosen); }
      catch (err) {
        toastError(err?.message || t('errors.save'));
        submit.disabled = false; return;
      }

      // colour the answers
      for (const c2 of qCards) {
        const qid = c2.dataset.qid;
        const correct = res.reveal?.[qid];
        c2.querySelectorAll('.opt').forEach((o) => {
          o.disabled = true;
          const k = o.getAttribute('data-key');
          if (k === correct) o.classList.add('opt--correct');
          else if (k === chosen[qid]) o.classList.add('opt--wrong');
        });
      }
      passMap.set(m.id, { module_id: m.id, score: res.score,
        total: res.total, passed: res.passed });
      if (res.passed) {
        fb.className = 'q-feedback q-feedback--ok';
        fb.textContent = t('course.passedScore', { s: res.score, tt: res.total });
        toast(t('course.passed'));
        if (res.cert_no) {
          enr.completed_at = new Date().toISOString();
          enr.cert_no = res.cert_no;
          submit.replaceWith(el('button', { class: 'btn btn--primary',
            style: 'width:100%;', text: t('course.viewCert'),
            onclick: () => certificate(course, enr) }));
          if (refreshOuter) refreshOuter();
        } else {
          submit.replaceWith(el('button', { class: 'btn btn--primary',
            style: 'width:100%;', text: t('course.nextModule'),
            onclick: () => modules(course, enr) }));
        }
      } else {
        fb.className = 'q-feedback q-feedback--no';
        fb.textContent = t('course.failedScore', { s: res.score, tt: res.total });
        submit.textContent = t('course.tryAgain');
        submit.disabled = false;
        const retry = () => {
          for (const c2 of qCards) c2.querySelectorAll('.opt').forEach((o) => {
            o.disabled = false;
            o.classList.remove('opt--correct', 'opt--wrong');
            o.setAttribute('aria-pressed', 'false');
          });
          for (const k of Object.keys(chosen)) delete chosen[k];
          fb.textContent = '';
          submit.removeEventListener('click', retry);
        };
        submit.addEventListener('click', retry, { once: true });
      }
    });
    container.append(submit, fb);
  }

  /* ------------------------- certificate ------------------------- */
  function certificate(course, enr) {
    clear(container);
    container.append(back(list));

    const name = `${profile.first_name} ${profile.last_name}`;
    const date = fmtDate(enr.completed_at || new Date().toISOString());

    const canvas = drawCert(name, course.title, enr.cert_no || '', date);
    canvas.style.width = '100%';
    canvas.style.height = 'auto';
    canvas.style.borderRadius = '10px';
    canvas.style.boxShadow = 'var(--shadow-2, 0 4px 18px rgba(0,0,0,.15))';
    container.append(canvas);

    container.append(el('div', { class: 'row mt-4', style: 'gap:8px;flex-wrap:wrap;' }, [
      el('button', { class: 'btn btn--primary', text: t('course.downloadImg'),
        onclick: () => {
          const a = el('a', {
            href: canvas.toDataURL('image/png'),
            download: `WODDI-Certificate-${(enr.cert_no || 'draft')}.png`,
          });
          document.body.append(a); a.click(); a.remove();
        } }),
      el('button', { class: 'btn btn--secondary', text: t('course.downloadPdf'),
        onclick: () => {
          const w = window.open('', '_blank');
          if (!w) { toastError(t('course.popupBlocked')); return; }
          w.document.write(`<!doctype html><html><head><title>${esc(enr.cert_no || 'Certificate')}</title>
            <style>@page{size:A4 landscape;margin:0}html,body{margin:0;padding:0}
            img{width:100vw;height:auto;display:block}</style></head>
            <body><img src="${canvas.toDataURL('image/png')}"
              onload="setTimeout(function(){window.print()},250)"></body></html>`);
          w.document.close();
        } }),
    ]));
  }

  function drawCert(name, courseTitle, certNo, date) {
    const W = 1600, H = 1131;                      // A4 landscape ratio
    const cv = document.createElement('canvas');
    cv.width = W; cv.height = H;
    const x = cv.getContext('2d');

    // paper + border
    x.fillStyle = '#FFFDF9'; x.fillRect(0, 0, W, H);
    x.strokeStyle = '#D4006A'; x.lineWidth = 10;
    x.strokeRect(40, 40, W - 80, H - 80);
    x.strokeStyle = '#7CB518'; x.lineWidth = 3;
    x.strokeRect(58, 58, W - 116, H - 116);
    // corner accents
    x.fillStyle = '#D4006A';
    [[40, 40], [W - 140, 40], [40, H - 140], [W - 140, H - 140]].forEach(([cx, cy]) => {
      x.globalAlpha = 0.12; x.fillRect(cx, cy, 100, 100); x.globalAlpha = 1;
    });

    x.textAlign = 'center';
    x.fillStyle = '#111111';
    x.font = '800 54px Inter, Arial, sans-serif';
    x.fillText('WODDI', W / 2, 170);
    x.font = '600 22px Inter, Arial, sans-serif';
    x.fillStyle = '#7CB518';
    x.fillText('WOMEN OF DIVINE DESTINY INITIATIVE  ·  THE NURTURER', W / 2, 208);

    x.fillStyle = '#D4006A';
    x.font = '800 64px Inter, Arial, sans-serif';
    x.fillText('Certificate of Completion', W / 2, 330);

    x.fillStyle = '#444444';
    x.font = '400 28px Inter, Arial, sans-serif';
    x.fillText('This certifies that', W / 2, 420);

    x.fillStyle = '#111111';
    x.font = 'italic 700 72px Georgia, serif';
    x.fillText(name, W / 2, 520);
    // underline
    x.strokeStyle = '#7CB518'; x.lineWidth = 3;
    x.beginPath(); x.moveTo(W / 2 - 420, 548); x.lineTo(W / 2 + 420, 548); x.stroke();

    x.fillStyle = '#444444';
    x.font = '400 28px Inter, Arial, sans-serif';
    x.fillText('has successfully completed all modules of the course', W / 2, 620);

    x.fillStyle = '#111111';
    x.font = '700 40px Inter, Arial, sans-serif';
    wrapText(x, courseTitle, W / 2, 690, 1200, 50);

    x.fillStyle = '#444444';
    x.font = '400 26px Inter, Arial, sans-serif';
    x.fillText(`Awarded on ${date}`, W / 2, 830);

    // signature area
    x.strokeStyle = '#111111'; x.lineWidth = 2;
    x.beginPath(); x.moveTo(W / 2 - 280, 950); x.lineTo(W / 2 + 280, 950); x.stroke();
    x.font = '600 24px Inter, Arial, sans-serif';
    x.fillStyle = '#111111';
    x.fillText('Founder & Chairperson', W / 2, 988);

    if (certNo) {
      x.textAlign = 'left';
      x.font = '600 22px Inter, Arial, sans-serif';
      x.fillStyle = '#D4006A';
      x.fillText(`Certificate No: ${certNo}`, 90, H - 90);
    }
    x.textAlign = 'right';
    x.font = '400 20px Inter, Arial, sans-serif';
    x.fillStyle = '#888888';
    x.fillText('woddicrm.org', W - 90, H - 90);
    return cv;
  }

  function wrapText(x, text, cx, y, maxW, lh) {
    const words = text.split(' ');
    let lineTxt = '';
    for (const w2 of words) {
      const test = lineTxt ? lineTxt + ' ' + w2 : w2;
      if (x.measureText(test).width > maxW && lineTxt) {
        x.fillText(lineTxt, cx, y); y += lh; lineTxt = w2;
      } else lineTxt = test;
    }
    if (lineTxt) x.fillText(lineTxt, cx, y);
  }

  function back(fn) {
    return el('button', { class: 'btn btn--quiet', style: 'margin-bottom:12px;',
      text: '\u2190 ' + t('app.back'), onclick: fn });
  }
  function errP() {
    return el('p', { class: 'muted', text: t('errors.loadHint') });
  }
}
