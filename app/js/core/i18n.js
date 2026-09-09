/**
 * WDOS i18n.
 * All user-facing text lives in /locales/{code}.json. English is the
 * complete reference catalogue; other locales fall back to English for
 * any missing key, so adding a language never breaks the interface.
 *
 * Locale files are dictionaries of dot-namespaced keys:
 *   { "members.title": "Members", ... }
 * Interpolation: t('members.count', { n: 41 }) with "{n} members".
 */
import { getConfig } from './config.js';

const SUPPORTED = ['en', 'fr', 'pt', 'ar', 'sw', 'ha', 'yo', 'ig'];
const RTL = new Set(['ar']);
const STORAGE_KEY = 'wdos.locale';

let base = {};      // English reference
let catalogue = {}; // active locale
let active = 'en';
let externalLoader = null;   // async (code) => dict | null
export function registerLocaleLoader(fn) { externalLoader = fn; }

async function fetchCatalogue(code) {
  const res = await fetch(`/locales/${code}.json`, { cache: 'no-cache' });
  if (!res.ok) throw new Error(`Locale "${code}" could not be loaded`);
  return res.json();
}

export async function initI18n() {
  base = await fetchCatalogue('en');
  const saved = localStorage.getItem(STORAGE_KEY);
  const wanted = saved || getConfig().defaultLocale;
  await setLocale(SUPPORTED.includes(wanted) ? wanted : 'en');
}

export async function setLocale(code) {
  if (!SUPPORTED.includes(code)) code = 'en';
  let dict = null;
  try {
    dict = await fetchCatalogue(code);
  } catch {
    // No bundled file for this language — try the AI-built dictionary
    // stored org-wide (Settings → Interface languages), else English.
    if (externalLoader) {
      try { dict = await externalLoader(code); } catch { dict = null; }
    }
  }
  if (!dict) {
    // language not built yet — keep the app in English words rather than
    // blank, and remember what was asked for so the selector shows it
    try { dict = await fetchCatalogue('en'); } catch { dict = {}; }
  }
  catalogue = dict;
  active = code;
  localStorage.setItem(STORAGE_KEY, code);
  document.documentElement.lang = code;
  document.documentElement.dir = RTL.has(code) ? 'rtl' : 'ltr';
}


export function getLocale() { return active; }
export function supportedLocales() { return [...SUPPORTED]; }

export function t(key, vars = {}) {
  let s = catalogue[key] ?? base[key] ?? key;
  for (const [k, v] of Object.entries(vars)) {
    s = s.replaceAll(`{${k}}`, String(v));
  }
  return s;
}

/** Format a date in the active locale. */
export function fmtDateTime(iso) {
  if (!iso) return '';
  return new Intl.DateTimeFormat(active, {
    dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso));
}

export function fmtDate(iso, opts = { dateStyle: 'medium' }) {
  if (!iso) return '';
  return new Intl.DateTimeFormat(active, opts).format(new Date(iso));
}

export function fmtNumber(n) {
  return new Intl.NumberFormat(active).format(n);
}
