/**
 * Phase 131 — one-minute cache of the volunteer_home() bundle.
 * The shell needs the unread counters and the leader flag; the home page
 * needs everything. Both read from here so a page render costs one RPC,
 * not two, and a tab switch inside the dashboard costs none.
 */
import { volunteerHome } from './db.js';

const TTL_MS = 60 * 1000;
let cache = { at: 0, data: null, promise: null };

export async function getHome(force = false) {
  const fresh = cache.data && (Date.now() - cache.at) < TTL_MS;
  if (fresh && !force) return cache.data;
  if (cache.promise && !force) return cache.promise;
  cache.promise = volunteerHome().then((d) => {
    cache = { at: Date.now(), data: d, promise: null };
    return d;
  }).catch((err) => { cache.promise = null; throw err; });
  return cache.promise;
}

export function invalidateHome() {
  cache = { at: 0, data: null, promise: null };
}
