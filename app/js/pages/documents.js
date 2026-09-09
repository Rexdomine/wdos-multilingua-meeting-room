import { el, esc, clear } from '../core/dom.js';
import { t, fmtDate } from '../core/i18n.js';
import {
  listDocFolders, createDocFolder, listDocuments, uploadDocument,
  setDocumentArchived, documentUrl, listOrgUnits,
} from '../core/db.js';
import { renderShell } from '../components/layout.js';
import { toast, toastError } from '../components/toast.js';
import { openModal } from '../components/modal.js';

const EXT_ICON = (name) => {
  const n = name.toLowerCase();
  if (/\.(png|jpe?g|gif|webp|svg)$/.test(n)) return '\u{1F5BC}\uFE0F';
  if (n.endsWith('.pdf')) return '\u{1F4D5}';
  if (/\.(csv|xlsx|xls)$/.test(n)) return '\u{1F4CA}';
  if (/\.(docx?|txt|md)$/.test(n)) return '\u{1F4C4}';
  return '\u{1F4CE}';
};

export async function render(root, _params, ctx) {
  const shell = renderShell(root, {
    profile: ctx.profile, modules: ctx.modules, titleKey: 'nav.documents',
  });
  const out = shell.outlet;
  const state = { folder: null, trail: [], showArchived: false };

  let units;
  try { units = await listOrgUnits(); } catch { units = []; }
  const myUnit = ctx.profile.org_unit_id;

  const area = el('div');
  out.append(area);
  await draw();
  return shell.teardown;

  async function draw() {
    clear(area);
    area.append(el('div', { class: 'card state' }, [
      el('div', { class: 'spinner' })]));
    let folders, docs = [];
    try {
      folders = await listDocFolders(state.folder?.id ?? null);
      if (state.folder) {
        docs = await listDocuments(state.folder.id, state.showArchived);
      }
    } catch {
      area.replaceChildren(el('div', { class: 'card state' }, [
        el('h3', { text: t('errors.loadTitle') }),
        el('button', { class: 'btn btn--quiet', text: t('app.retry'),
          onclick: draw }),
      ]));
      return;
    }
    clear(area);

    /* breadcrumb */
    const crumb = el('p', { class: 'muted mb-4' });
    crumb.append(el('a', { href: '#/documents', text: t('nav.documents'),
      onclick: (e) => { e.preventDefault();
        state.folder = null; state.trail = []; draw(); } }));
    state.trail.forEach((f, i) => {
      crumb.append(' / ', el('a', { href: '#', text: f.name,
        onclick: (e) => { e.preventDefault();
          state.trail = state.trail.slice(0, i + 1);
          state.folder = f; draw(); } }));
    });
    area.append(crumb);

    /* toolbar */
    const newName = el('input', { class: 'input', maxlength: '120',
      placeholder: t('docs.newFolder'), style: 'max-width:240px;' });
    const unitSel = el('select', { class: 'select',
      style: 'max-width:260px;' },
      units.map((u) => el('option', { value: u.id,
        selected: u.id === (state.folder?.org_unit_id ?? myUnit) || null,
        text: `${t(`org.${u.level}`)} — ${u.name}` })));
    const fileIn = el('input', { type: 'file', hidden: true });
    fileIn.addEventListener('change', async () => {
      const f = fileIn.files[0];
      if (!f || !state.folder) return;
      try {
        await uploadDocument(state.folder.id, f);
        toast(t('docs.uploaded'));
        draw();
      } catch { toastError(t('errors.save')); }
      fileIn.value = '';
    });
    const bar = el('div', { class: 'toolbar' }, [
      newName,
      state.folder ? null : unitSel,
      el('button', { class: 'btn btn--quiet', text: t('docs.createFolder'),
        onclick: async (e) => {
          if (!newName.value.trim()) return;
          e.target.disabled = true;
          try {
            await createDocFolder({
              name: newName.value.trim(),
              parent_id: state.folder?.id ?? null,
              org_unit_id: state.folder?.org_unit_id ?? unitSel.value,
            });
            newName.value = '';
            toast(t('docs.folderCreated'));
            draw();
          } catch (err) {
            toastError(String(err?.message ?? '').includes('duplicate')
              ? t('docs.errDuplicate') : t('errors.save'));
          } finally { e.target.disabled = false; }
        } }),
      el('span', { class: 'grow' }),
      state.folder ? el('label', { class: 'chip' }, [
        (() => { const cb = el('input', { type: 'checkbox' });
          cb.checked = state.showArchived;
          cb.addEventListener('change', () => {
            state.showArchived = cb.checked; draw(); });
          return cb; })(),
        ' ' + t('docs.showArchived'),
      ]) : null,
      state.folder ? el('button', { class: 'btn btn--primary',
        text: t('docs.upload'), onclick: () => fileIn.click() }) : null,
      fileIn,
    ]);
    area.append(bar);

    /* folders grid */
    if (folders.length > 0) {
      const grid = el('div', { class: 'stats' });
      for (const f of folders) {
        grid.append(el('button', { class: 'card folder-card',
          onclick: () => { state.trail.push(f); state.folder = f; draw(); },
        }, [
          el('span', { style: 'font-size:26px;', text: '\u{1F4C1}' }),
          el('strong', { text: f.name }),
          el('span', { class: 'muted',
            text: units.find((u) => u.id === f.org_unit_id)?.name ?? '' }),
        ]));
      }
      area.append(grid);
    }

    /* documents list */
    if (state.folder) {
      if (docs.length === 0 && folders.length === 0) {
        area.append(el('div', { class: 'card state mt-4' }, [
          el('h3', { text: t('docs.emptyTitle') }),
          el('p', { text: t('docs.emptyHint') }),
        ]));
      }
      for (const d of docs) {
        const row = el('div', { class: 'card mt-4 row',
          style: d.archived ? 'opacity:.55;' : '' }, [
          el('span', { style: 'font-size:22px;', text: EXT_ICON(d.name) }),
          el('div', { class: 'grow' }, [
            el('strong', { text: d.name }),
            el('div', { class: 'muted',
              text: fmtDate(d.created_at) +
                (d.archived ? ` · ${t('docs.archived')}` : '') }),
          ]),
          el('button', { class: 'btn btn--quiet', text: t('docs.view'),
            onclick: () => viewDocument(d) }),
          el('a', { class: 'btn btn--quiet', text: t('docs.download'),
            href: documentUrl(d.path), download: d.name,
            target: '_blank', rel: 'noopener' }),
          el('button', { class: 'btn btn--quiet',
            text: d.archived ? t('docs.unarchive') : t('docs.archive'),
            onclick: async (e) => {
              e.target.disabled = true;
              try {
                await setDocumentArchived(d.id, !d.archived);
                toast(t('docs.updated'));
                draw();
              } catch { toastError(t('errors.save'));
                e.target.disabled = false; }
            } }),
        ]);
        area.append(row);
      }
    }
  }

  async function viewDocument(d) {
    const url = documentUrl(d.path);
    const name = d.name.toLowerCase();
    const body = el('div');
    const foot = el('div', { class: 'row mt-4' }, [
      el('span', { class: 'grow' }),
      el('a', { class: 'btn btn--primary', text: t('docs.download'),
        href: url, download: d.name, target: '_blank', rel: 'noopener' }),
    ]);
    if (/\.(png|jpe?g|gif|webp|svg)$/.test(name)) {
      body.append(el('img', { src: url, alt: d.name,
        style: 'max-width:100%;border-radius:10px;' }));
    } else if (name.endsWith('.pdf')) {
      body.append(el('iframe', { src: url,
        style: 'width:100%;height:70vh;border:1px solid var(--line);' +
          'border-radius:10px;' }));
    } else if (/\.(csv|txt|md)$/.test(name)) {
      body.append(el('div', { class: 'spinner' }));
      try {
        const text = await (await fetch(url)).text();
        clear(body);
        if (name.endsWith('.csv')) body.append(csvTable(text));
        else body.append(el('pre', {
          style: 'white-space:pre-wrap;max-height:65vh;overflow:auto;',
          text: text.slice(0, 200000) }));
      } catch {
        clear(body);
        body.append(el('p', { class: 'field__error', text: t('errors.load') }));
      }
    } else if (/\.docx$/.test(name)) {
      body.append(el('div', { class: 'spinner' }));
      try {
        await loadVendor('/assets/vendor/mammoth.browser.min.js', 'mammoth');
        const buf = await (await fetch(url)).arrayBuffer();
        const out = await window.mammoth.convertToHtml({ arrayBuffer: buf });
        clear(body);
        const doc = el('div', {
          style: 'max-height:65vh;overflow:auto;line-height:1.6;' });
        doc.innerHTML = out.value;
        body.append(doc);
      } catch {
        clear(body);
        body.append(el('p', { class: 'muted', text: t('docs.noPreview') }));
      }
    } else if (/\.(xlsx|xls)$/.test(name)) {
      body.append(el('div', { class: 'spinner' }));
      try {
        await loadVendor('/assets/vendor/xlsx.full.min.js', 'XLSX');
        const buf = await (await fetch(url)).arrayBuffer();
        const wb = window.XLSX.read(buf, { type: 'array' });
        clear(body);
        const sheetArea = el('div');
        const chips = el('div', { class: 'row mb-4' },
          wb.SheetNames.map((sn, i) => el('button', {
            class: `chip${i === 0 ? ' chip--on' : ''}`, text: sn,
            onclick: (e) => {
              chips.querySelectorAll('.chip')
                .forEach((c) => c.classList.remove('chip--on'));
              e.target.classList.add('chip--on');
              showSheet(sn);
            } })));
        body.append(chips, sheetArea);
        showSheet(wb.SheetNames[0]);
        function showSheet(sn) {
          const rows = window.XLSX.utils
            .sheet_to_json(wb.Sheets[sn], { header: 1 }).slice(0, 500);
          const wrap = el('div', { class: 'table-wrap',
            style: 'max-height:60vh;overflow:auto;' });
          const tbl = el('table', { class: 'table' });
          tbl.innerHTML =
            (rows[0] ? '<thead><tr>' + rows[0].map((h) =>
              `<th>${esc(String(h ?? ''))}</th>`).join('') +
              '</tr></thead>' : '') +
            '<tbody>' + rows.slice(1).map((r) =>
              `<tr style="cursor:default;">${(r ?? []).map((c) =>
                `<td>${esc(String(c ?? ''))}</td>`).join('')}</tr>`)
              .join('') + '</tbody>';
          wrap.append(tbl);
          sheetArea.replaceChildren(wrap);
        }
      } catch {
        clear(body);
        body.append(el('p', { class: 'muted', text: t('docs.noPreview') }));
      }
    } else {
      body.append(el('p', { class: 'muted', text: t('docs.noPreview') }));
    }
    body.append(foot);
    openModal(d.name, body);
  }
}

const loadedVendors = new Map();
function loadVendor(src, globalName) {
  if (window[globalName]) return Promise.resolve();
  if (loadedVendors.has(src)) return loadedVendors.get(src);
  const p = new Promise((resolve, reject) => {
    const sc = document.createElement('script');
    sc.src = src;
    sc.onload = resolve;
    sc.onerror = reject;
    document.head.append(sc);
  });
  loadedVendors.set(src, p);
  return p;
}

/** Small CSV renderer with quoted-field support. */
function csvTable(text) {
  const rows = [];
  let row = [], cell = '', q = false;
  for (let i = 0; i < text.length && rows.length < 500; i += 1) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i += 1; }
      else if (c === '"') q = false;
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i += 1;
      row.push(cell); rows.push(row); row = []; cell = '';
    } else cell += c;
  }
  if (cell !== '' || row.length) { row.push(cell); rows.push(row); }
  const wrap = el('div', { class: 'table-wrap',
    style: 'max-height:65vh;overflow:auto;' });
  const tbl = el('table', { class: 'table' });
  tbl.innerHTML =
    (rows[0] ? `<thead><tr>${rows[0].map((h) =>
      `<th>${esc(h)}</th>`).join('')}</tr></thead>` : '') +
    `<tbody>${rows.slice(1).map((r) =>
      `<tr style="cursor:default;">${r.map((c) =>
        `<td>${esc(c)}</td>`).join('')}</tr>`).join('')}</tbody>`;
  wrap.append(tbl);
  return wrap;
}
