/**
 * WDOS data layer.
 * The ONLY module allowed to talk to Supabase. Every page and component
 * goes through the functions exported here, which keeps the application
 * vendor-independent: replacing Supabase means rewriting this file, not
 * the app.
 *
 * The Supabase client is the official single-file build, downloaded once
 * and stored at /assets/vendor/supabase.js (loaded by index.html before
 * the app starts). No build tools, no runtime CDN dependency — the app
 * owns its copy. See docs/SETUP.md §3.
 */
import { getConfig } from './config.js';

function createClient(url, key, options) {
  if (!window.supabase?.createClient) {
    throw new Error(
      'assets/vendor/supabase.js is missing — see docs/SETUP.md, Part E'
    );
  }
  return window.supabase.createClient(url, key, options);
}

let client = null;

export function initDb() {
  const { supabaseUrl, supabaseAnonKey } = getConfig();
  client = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true },
  });
  return client;
}

export function db() {
  if (!client) throw new Error('initDb() must run before db()');
  return client;
}

/* ------------------------------------------------------------------ */
/* Auth                                                                */
/* ------------------------------------------------------------------ */

export async function signIn(email, password) {
  const { data, error } = await db().auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data.session;
}

export async function signOut() {
  markUserSignOut();
  authLog('user_sign_out');
  const { error } = await db().auth.signOut();
  if (error) throw error;
}

export async function getSession() {
  const { data, error } = await db().auth.getSession();
  if (error) throw error;
  return data.session;
}

export function onAuthChange(handler) {
  return db().auth.onAuthStateChange((event, session) => handler(session, event));
}

/* Auth diagnostics (v67.1): a ring buffer of the last 30 auth events with
   timestamps, page and build, kept in localStorage so the reason for an
   unexpected sign-out can be read afterwards (login page + #/doctor). */
export function authLog(event, extra = {}) {
  try {
    const key = 'wdos.authlog';
    const arr = JSON.parse(localStorage.getItem(key) || '[]');
    arr.push({ at: new Date().toISOString(), event, hash: location.hash, build: APP_VERSION, ...extra });
    localStorage.setItem(key, JSON.stringify(arr.slice(-30)));
  } catch { /* storage unavailable */ }
}
export function readAuthLog() {
  try { return JSON.parse(localStorage.getItem('wdos.authlog') || '[]'); } catch { return []; }
}
let userSignOut = false;
export function markUserSignOut() { userSignOut = true; }
export function wasUserSignOut() { const v = userSignOut; userSignOut = false; return v; }

/* ------------------------------------------------------------------ */
/* Profiles / Members                                                  */
/* ------------------------------------------------------------------ */

const PROFILE_COLUMNS =
  'id, membership_no, first_name, last_name, email, phone, network, status, ' +
  'org_unit_id, preferred_locale, birth_date, created_at, updated_at';

export async function getMyProfile() {
  const session = await getSession();
  if (!session) return null;
  // The profile row is created by a database trigger the instant the auth
  // user appears. Right after sign-in (Google most of all) the SELECT can
  // arrive a moment before that row is visible, so a single miss is not an
  // error: retry a few times, then report "no row yet" as null rather than
  // throwing the person to a dead screen. maybeSingle() returns null (not
  // an error) when zero rows match.
  let lastErr = null;
  for (let i = 0; i < 6; i += 1) {
    const { data, error } = await db()
      .from('profiles').select(PROFILE_COLUMNS).eq('id', session.user.id).maybeSingle();
    if (!error && data) return data;
    lastErr = error;
    await new Promise((r) => setTimeout(r, 250));
  }
  if (lastErr) throw lastErr;
  return null;
}

/** True once the signed-in user has a profile row. Used by the OAuth
 *  landing guard so a brand-new Google sign-in is not bounced as "no
 *  profile" before the trigger has run. */
export async function hasProfile() {
  const session = await getSession();
  if (!session) return false;
  const { data } = await db()
    .from('profiles').select('id').eq('id', session.user.id).maybeSingle();
  return !!data;
}

/**
 * List members visible to the current user (RLS enforces scope).
 * @param {object} opts { search, status, network, page, pageSize }
 */
export async function listMembers(opts = {}) {
  const { search = '', status = '', network = '', page = 0, pageSize = 25 } = opts;
  let q = db()
    .from('field_members')
    .select(PROFILE_COLUMNS, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);

  if (status) q = q.eq('status', status);
  if (network) q = q.eq('network', network);
  if (search) {
    const s = search.replaceAll('%', '').replaceAll(',', '');
    q = q.or(
      `first_name.ilike.%${s}%,last_name.ilike.%${s}%,` +
      `email.ilike.%${s}%,membership_no.ilike.%${s}%`
    );
  }
  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function getMember(id) {
  const { data, error } = await db()
    .from('profiles').select(PROFILE_COLUMNS).eq('id', id).single();
  if (error) throw error;
  return data;
}

export async function updateMember(id, patch) {
  const allowed = ['first_name', 'last_name', 'phone', 'network',
    'status', 'org_unit_id', 'preferred_locale', 'membership_no'];
  const clean = Object.fromEntries(
    Object.entries(patch).filter(([k]) => allowed.includes(k))
  );
  const { data, error } = await db()
    .from('profiles').update(clean).eq('id', id)
    .select(PROFILE_COLUMNS).single();
  if (error) throw error;
  return data;
}

/* ------------------------------------------------------------------ */
/* Organisational structure                                            */
/* ------------------------------------------------------------------ */

export async function listCountryLevelNames() {
  const { data, error } = await db()
    .from('country_level_names')
    .select('country_id, level, local_name');
  if (error) throw error;
  const map = new Map();
  for (const row of data) {
    if (!map.has(row.country_id)) map.set(row.country_id, {});
    map.get(row.country_id)[row.level] = row.local_name;
  }
  return map;
}

export async function listOrgUnits() {
  const { data, error } = await db()
    .from('org_units')
    .select('id, parent_id, level, name, country_iso, is_active')
    .eq('is_active', true)
    .order('name');
  if (error) throw error;
  return data;
}

/* ------------------------------------------------------------------ */
/* Dashboard aggregates (head-only count queries; cheap under RLS)     */
/* ------------------------------------------------------------------ */

async function countWhere(build) {
  let q = db().from('field_members')
    .select('id', { count: 'exact', head: true });
  q = build(q);
  const { count, error } = await q;
  if (error) throw error;
  return count ?? 0;
}

export async function getDashboardStats() {
  const [total, active, pipeline, training] = await Promise.all([
    countWhere((q) => q),
    countWhere((q) => q.eq('status', 'active')),
    countWhere((q) => q.in('status', ['applicant', 'under_review', 'approved'])),
    countWhere((q) => q.eq('status', 'in_training')),
  ]);
  return { total, active, pipeline, training };
}

/* ------------------------------------------------------------------ */
/* Roles (current user)                                                */
/* ------------------------------------------------------------------ */

const APPROVER_ROLES = new Set(['super_admin', 'executive_director', 'hq_team',
  'country_rep', 'deputy_country_rep', 'state_coordinator']);

export async function getMyRoles() {
  const session = await getSession();
  if (!session) return [];
  const { data, error } = await db()
    .from('role_assignments')
    .select('role, org_unit_id, org_unit:org_units(name, level)')
    .eq('profile_id', session.user.id)
    .is('ends_at', null);
  if (error) throw error;
  return data;
}

/** My teammates — anyone sharing one of my leadership seats. */
export const myTeam = () => appRpc('my_team', {});

/** Everyone at or below any leadership seat I hold — my own region's
 *  chart, vacant seats shown honestly. */
export const mySubtree = () => appRpc('my_subtree', {});

export function isApprover(roles) {
  return roles.some((r) => APPROVER_ROLES.has(r.role));
}

/* ------------------------------------------------------------------ */
/* Recruitment — applications                                          */
/* ------------------------------------------------------------------ */

const APP_COLUMNS =
  'id, first_name, last_name, email, phone, network, org_unit_id, motivation, ' +
  'preferred_locale, status, reviewer_id, reviewer_notes, recommended_at, ' +
  'decided_by, decision_reason, decided_at, profile_id, created_at, updated_at';

/** Public submission — works without a session (anon RLS insert policy).
 *  No RETURNING: anonymous visitors may write an application but never
 *  read one back, so we must not ask for the row. */
/** Phase 119 — Google sign-in. Replaces the password step only; the
 *  registration forms remain the door (they capture the age question
 *  that decides the network). Redirects back to this origin. */
export const signInWithGoogle = () =>
  db().auth.signInWithOAuth({
    provider: 'google',
    options: {
      // Come back to the app root with the hash router intact. The
      // fragment tokens Supabase appends are handled by the OAuth guard
      // in router.js.
      redirectTo: window.location.origin + window.location.pathname + '#/',
      queryParams: { prompt: 'select_account' },
    },
  });

export async function submitApplication(fields) {
  const { error } = await db()
    .from('applications')
    .insert({
      first_name: fields.first_name,
      last_name: fields.last_name,
      email: fields.email,
      phone: fields.phone || null,
      network: fields.network,
      org_unit_id: fields.org_unit_id,
      motivation: fields.motivation,
      preferred_locale: fields.preferred_locale || 'en',
    });
  if (error) throw error;
}

export async function listApplications(opts = {}) {
  const { status = '', page = 0, pageSize = 25 } = opts;
  let q = db()
    .from('applications')
    .select(APP_COLUMNS, { count: 'exact' })
    .order('created_at', { ascending: true })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (status) q = q.eq('status', status);
  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function getApplication(id) {
  const { data, error } = await db()
    .from('applications').select(APP_COLUMNS).eq('id', id).single();
  if (error) throw error;
  return data;
}

// Phase 109: under load spikes on the free tier, a request can fail once
// and succeed a moment later. Reads get ONE quiet retry with a short
// jittered pause before the person ever sees an error. Anything that
// changes data is never retried, so nothing can double-send.
const NO_RETRY_PREFIXES = ['report_s', 'report_r', 'report_n', 'reporting_rem', 'hq_update', 'hq_set', 'hq_end', 'hq_link',
  'send_', 'dispatch_', 'submit_', 'set_',
  'record_', 'promote_', 'decide_', 'approve_', 'hold_', 'publish_',
  'create_', 'claim_', 'notify_', 'review_', 'recommend_', 'file_',
  'add_', 'assign_', 'mark_', 'update_', 'delete_', 'reject_'];

async function appRpc(name, args) {
  const { data, error } = await db().rpc(name, args);
  if (!error) return data;
  const mutates = NO_RETRY_PREFIXES.some((p) => name.startsWith(p));
  if (mutates) throw error;
  await new Promise((r) => setTimeout(r, 500 + Math.random() * 400));
  const second = await db().rpc(name, args);
  if (second.error) throw second.error;
  return second.data;
}

export const reviewApplication = (id, notes) =>
  appRpc('review_application', { app_id: id, notes: notes || null });
export const recommendApplication = (id, notes) =>
  appRpc('recommend_application', { app_id: id, notes });
export const decideApplication = (id, approve, reason) =>
  appRpc('decide_application', { app_id: id, approve, reason });

/* ------------------------------------------------------------------ */
/* Organisation & Leadership                                           */
/* ------------------------------------------------------------------ */

export const createOrgUnit = (parent, name, iso) =>
  appRpc('create_org_unit', { parent, unit_name: name, iso: iso || null });

export const appointLeader = (profileId, role, unit, reason) =>
  appRpc('appoint_leader', {
    target_profile: profileId, new_role: role, unit, reason,
  });

export const endAppointment = (assignmentId, reason) =>
  appRpc('end_appointment', { assignment_id: assignmentId, reason });

/** Current (and optionally past) leadership at one unit. */
export async function listUnitLeaders(unitId, { includePast = false } = {}) {
  let q = db()
    .from('role_assignments')
    .select('id, role, starts_at, ends_at, ' +
      'person:profiles!role_assignments_profile_id_fkey' +
      '(id, first_name, last_name, email, membership_no)')
    .eq('org_unit_id', unitId)
    .order('starts_at', { ascending: false });
  if (!includePast) q = q.is('ends_at', null);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

/** Members eligible for appointment (good standing), searchable. */
export const searchHqPeople = (s) =>
  appRpc('search_staff_assignees', { s: s || '' });

export const amIStaff = () =>
  appRpc('am_i_staff', {}).catch(() => false);

export async function searchAppointableMembers(search) {
  // HQ also sees active staff in the picker (definer RPC; empty for others)
  const staffP = appRpc('search_staff_assignees', { s: search || '' })
    .then((rows) => (rows || []).map((r) => ({
      id: r.id, first_name: r.first_name, last_name: r.last_name,
      email: r.email, membership_no: r.position_title, status: 'active',
    })))
    .catch(() => []);
  let rows = [];
  try {
    let q = db()
      .from('field_members')
      .select('id, first_name, last_name, email, membership_no, status')
      .in('status', ['applicant', 'under_review', 'approved', 'activated',
        'in_training', 'active', 'reinstated'])
      .order('last_name')
      .limit(25);
    if (search) {
      const s2 = search.replaceAll('%', '').replaceAll(',', '');
      q = q.or(
        `first_name.ilike.%${s2}%,last_name.ilike.%${s2}%,` +
        `email.ilike.%${s2}%,membership_no.ilike.%${s2}%`
      );
    }
    const { data, error } = await q;
    if (!error) rows = data || [];
  } catch { rows = []; }
  const staffRows = await staffP;
  const seen = new Set(rows.map((r) => r.id));
  return [...rows, ...staffRows.filter((r) => !seen.has(r.id))].slice(0, 40);
}

/* ------------------------------------------------------------------ */
/* Tasks                                                               */
/* ------------------------------------------------------------------ */

const TASK_COLUMNS =
  'id, title, details, org_unit_id, assigned_to, assigned_by, priority, ' +
  'status, requires_approval, due_on, completed_at, created_at, updated_at, tags, ' +
  'assignee:profiles!tasks_assigned_to_fkey(id, first_name, last_name), ' +
  'assigner:profiles!tasks_assigned_by_fkey(id, first_name, last_name)';

export async function listTasks(opts = {}) {
  const { scope = 'mine', status = '', page = 0, pageSize = 25,
    priority = '', overdueOnly = false, search = '', sort = 'due',
    dueFrom = '', dueTo = '' } = opts;
  const session = await getSession();
  let q = db()
    .from('tasks')
    .select(TASK_COLUMNS, { count: 'exact' })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (sort === 'priority') {
    q = q.order('priority', { ascending: false })
         .order('due_on', { ascending: true, nullsFirst: false });
  } else if (sort === 'newest') {
    q = q.order('created_at', { ascending: false });
  } else {
    q = q.order('due_on', { ascending: true, nullsFirst: false })
         .order('created_at', { ascending: false });
  }
  if (scope === 'mine') q = q.eq('assigned_to', session.user.id);
  if (scope === 'assigned') q = q.eq('assigned_by', session.user.id);
  // scope 'area': no extra filter — RLS already limits to visible tasks
  if (status) q = q.eq('status', status);
  if (priority) q = q.eq('priority', priority);
  if (overdueOnly) {
    q = q.in('status', ['not_started', 'in_progress'])
         .lt('due_on', new Date().toISOString().slice(0, 10));
  }
  if (search) {
    const sv = search.replaceAll('%', '').replaceAll(',', '');
    q = q.ilike('title', `%${sv}%`);
  }
  if (dueFrom) q = q.gte('due_on', dueFrom);
  if (dueTo) q = q.lte('due_on', dueTo);
  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function createTask(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('tasks')
    .insert({
      title: fields.title,
      details: fields.details || null,
      tags: fields.tags || [],
      org_unit_id: fields.org_unit_id,
      assigned_to: fields.assigned_to,
      assigned_by: session.user.id,
      priority: fields.priority,
      requires_approval: Boolean(fields.requires_approval),
      due_on: fields.due_on || null,
    })
    .select(TASK_COLUMNS)
    .single();
  if (error) throw error;
  return data;
}

export async function setTaskStatus(id, status) {
  const { data, error } = await db()
    .from('tasks').update({ status }).eq('id', id)
    .select(TASK_COLUMNS).single();
  if (error) throw error;
  return data;
}

/* ------------------------------------------------------------------ */
/* Meetings & attendance                                               */
/* ------------------------------------------------------------------ */

const MEETING_COLUMNS =
  'id, title, agenda, org_unit_id, organiser, mode, platform, audience, location, starts_at, ' +
  'ends_at, status, minutes, created_at, updated_at, ' +
  'host:profiles!meetings_organiser_fkey(id, first_name, last_name)';

export async function listMeetings(opts = {}) {
  const { scope = 'upcoming', page = 0, pageSize = 25 } = opts;
  const nowIso = new Date().toISOString();
  let q = db()
    .from('meetings')
    .select(MEETING_COLUMNS, { count: 'exact' })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (scope === 'upcoming') {
    q = q.gte('ends_at', nowIso).order('starts_at', { ascending: true });
  } else {
    q = q.lt('ends_at', nowIso).order('starts_at', { ascending: false });
  }
  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function createMeeting(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('meetings')
    .insert({
      title: fields.title,
      agenda: fields.agenda || null,
      org_unit_id: fields.org_unit_id,
      organiser: session.user.id,
      mode: fields.mode,
      platform: fields.platform || 'woddi',
      audience: fields.audience || 'unit',
      location: fields.location || null,
      starts_at: fields.starts_at,
      ends_at: fields.ends_at,
    })
    .select(MEETING_COLUMNS)
    .single();
  if (error) throw error;
  return data;
}

export async function updateMeeting(id, patch) {
  const allowed = ['status', 'minutes', 'location', 'agenda',
    'starts_at', 'ends_at', 'mode'];
  const clean = Object.fromEntries(
    Object.entries(patch).filter(([k]) => allowed.includes(k)));
  const { data, error } = await db()
    .from('meetings').update(clean).eq('id', id)
    .select(MEETING_COLUMNS).single();
  if (error) throw error;
  return data;
}

/** Members whose home unit is the given unit (for the attendance sheet). */
export async function listUnitMembers(unitId) {
  const { data, error } = await db()
    .from('profiles')
    .select('id, first_name, last_name, membership_no, status')
    .eq('org_unit_id', unitId)
    .in('status', ['activated', 'in_training', 'active', 'reinstated', 'inactive'])
    .order('last_name');
  if (error) throw error;
  return data;
}

export async function getAttendance(meetingId) {
  const { data, error } = await db()
    .from('meeting_attendance')
    .select('id, profile_id, present')
    .eq('meeting_id', meetingId);
  if (error) throw error;
  return data;
}

/** Upsert attendance marks: entries = [{profile_id, present}] */
export async function saveAttendance(meetingId, entries) {
  const session = await getSession();
  const rows = entries.map((e) => ({
    meeting_id: meetingId,
    profile_id: e.profile_id,
    present: e.present,
    recorded_by: session.user.id,
    recorded_at: new Date().toISOString(),
  }));
  const { error } = await db()
    .from('meeting_attendance')
    .upsert(rows, { onConflict: 'meeting_id,profile_id' });
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Reports (RLS-scoped aggregates)                                     */
/* ------------------------------------------------------------------ */

export async function getReports() {
  // Resilient: one failed analytics RPC renders as an empty widget, not a
  // dead Reports page (audit fix, Phase 88).
  const soft = (name, args) => appRpc(name, args).catch(() => null);
  const [membership, growth, recruitment, tasks, meetings, coverage] =
    await Promise.all([
      soft('report_membership', {}),
      soft('report_monthly_growth', { months: 6 }),
      soft('report_recruitment', {}),
      soft('report_tasks', { days: 30 }),
      soft('report_meetings', { days: 30 }),
      soft('report_leadership_coverage', {}),
    ]);
  return { membership, growth, recruitment, tasks, meetings, coverage };
}

/* ------------------------------------------------------------------ */
/* Announcements                                                       */
/* ------------------------------------------------------------------ */

const ANN_COLUMNS =
  'id, title, body, org_unit_id, network, priority, audience, author_id, ' +
  'created_at, ' +
  'author:profiles!announcements_author_id_fkey(id, first_name, last_name)';

export async function listAnnouncements(opts = {}) {
  const { page = 0, pageSize = 20 } = opts;
  const session = await getSession();
  const [{ data, error, count }, readsRes] = await Promise.all([
    db().from('announcements')
      .select(ANN_COLUMNS, { count: 'exact' })
      .order('created_at', { ascending: false })
      .range(page * pageSize, page * pageSize + pageSize - 1),
    db().from('announcement_reads')
      .select('announcement_id')
      .eq('profile_id', session.user.id),
  ]);
  if (error) throw error;
  if (readsRes.error) throw readsRes.error;
  const readSet = new Set(readsRes.data.map((r) => r.announcement_id));
  return {
    rows: data.map((a) => ({ ...a, read: readSet.has(a.id) })),
    total: count ?? 0,
  };
}

export async function postAnnouncement(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('announcements')
    .insert({
      title: fields.title,
      body: fields.body,
      org_unit_id: fields.org_unit_id,
      network: fields.network || null,
      priority: fields.priority,
      audience: fields.audience || 'all',
      author_id: session.user.id,
    })
    .select(ANN_COLUMNS)
    .single();
  if (error) throw error;
  return data;
}

export async function markAnnouncementRead(annId) {
  const session = await getSession();
  const { error } = await db()
    .from('announcement_reads')
    .upsert({ announcement_id: annId, profile_id: session.user.id },
      { onConflict: 'announcement_id,profile_id', ignoreDuplicates: true });
  if (error) throw error;
}

export const getAnnouncementReach = (annId) =>
  appRpc('announcement_reach', { ann_id: annId });

/* ------------------------------------------------------------------ */
/* Personal dashboard ("my day")                                       */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* System health: does the database match this build?                  */
/* ------------------------------------------------------------------ */

/** The migration number this build of the app requires. Bump with every
 *  new migration; the shell warns HQ when the database is behind. */
export const EXPECTED_SCHEMA_VERSION = 115;
export const APP_VERSION = '68.7-azure-invite-vercel';

export async function getSchemaStatus() {
  try {
    const { data, error } = await db()
      .from('schema_migrations')
      .select('version, name, applied_at')
      .order('version');
    if (error) throw error;
    const applied = new Set(data.map((r) => r.version));
    const missing = [];
    for (let v = 1; v <= EXPECTED_SCHEMA_VERSION; v += 1) {
      if (!applied.has(v)) missing.push(v);
    }
    return { known: true, applied: data, missing };
  } catch {
    // Table absent = migration 011 itself not applied yet.
    return { known: false, applied: [], missing: [EXPECTED_SCHEMA_VERSION] };
  }
}

/* ------------------------------------------------------------------ */
/* Module access (HQ-controlled workspaces)                            */
/* ------------------------------------------------------------------ */

export async function getMyModules() {
  const { data, error } = await db().rpc('my_modules');
  if (error) throw error;
  return new Set(data.map((r) => (typeof r === 'string' ? r : r.my_modules)));
}

export async function listModuleAccess() {
  const { data, error } = await db()
    .from('module_access').select('role, module');
  if (error) throw error;
  return data;
}

export async function setModuleAccess(role, module, enabled) {
  if (enabled) {
    const { error } = await db()
      .from('module_access').upsert({ role, module },
        { onConflict: 'role,module', ignoreDuplicates: true });
    if (error) throw error;
  } else {
    const { error } = await db()
      .from('module_access').delete().eq('role', role).eq('module', module);
    if (error) throw error;
  }
}

/* ------------------------------------------------------------------ */
/* Programmes & beneficiaries                                          */
/* ------------------------------------------------------------------ */

export async function listProgrammes() {
  const { data, error } = await db()
    .from('programmes')
    .select('id, code, name, description, network, is_active')
    .eq('is_active', true)
    .order('code');
  if (error) throw error;
  return data;
}

export async function updateProgramme(id, patch) {
  const allowed = ['name', 'description', 'network', 'is_active'];
  const clean = Object.fromEntries(
    Object.entries(patch).filter(([k]) => allowed.includes(k)));
  const { data, error } = await db()
    .from('programmes').update(clean).eq('id', id)
    .select('id, code, name, description, network, is_active').single();
  if (error) throw error;
  return data;
}

const EVENT_COLUMNS =
  'id, programme_id, org_unit_id, title, event_date, location, notes, ' +
  'created_by, created_at';

export async function listProgrammeEvents(programmeId, opts = {}) {
  const { page = 0, pageSize = 20 } = opts;
  const { data, error, count } = await db()
    .from('programme_events')
    .select(EVENT_COLUMNS, { count: 'exact' })
    .eq('programme_id', programmeId)
    .order('event_date', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function createProgrammeEvent(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('programme_events')
    .insert({
      programme_id: fields.programme_id,
      org_unit_id: fields.org_unit_id,
      title: fields.title,
      event_date: fields.event_date,
      location: fields.location || null,
      notes: fields.notes || null,
      created_by: session.user.id,
    })
    .select(EVENT_COLUMNS).single();
  if (error) throw error;
  return data;
}

export async function listBeneficiaries(search = '') {
  let q = db()
    .from('beneficiaries')
    .select('id, full_name, age_band, org_unit_id, notes, created_at')
    .order('full_name')
    .limit(15);
  if (search) {
    const s = search.replaceAll('%', '').replaceAll(',', '');
    q = q.ilike('full_name', `%${s}%`);
  }
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function addBeneficiary(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('beneficiaries')
    .insert({
      full_name: fields.full_name,
      age_band: fields.age_band,
      org_unit_id: fields.org_unit_id,
      notes: fields.notes || null,
      created_by: session.user.id,
    })
    .select('id, full_name, age_band, org_unit_id, notes, created_at')
    .single();
  if (error) throw error;
  return data;
}

export async function listServices(eventId) {
  const { data, error } = await db()
    .from('service_records')
    .select('id, service, outcome, recorded_at, ' +
      'who:beneficiaries!service_records_beneficiary_id_fkey' +
      '(id, full_name, age_band)')
    .eq('event_id', eventId)
    .order('recorded_at', { ascending: false });
  if (error) throw error;
  return data;
}

export async function addService(eventId, beneficiaryId, service, outcome) {
  const session = await getSession();
  const { error } = await db()
    .from('service_records')
    .insert({
      event_id: eventId,
      beneficiary_id: beneficiaryId,
      service,
      outcome: outcome || null,
      recorded_by: session.user.id,
    });
  if (error) throw error;
}

export async function listVolunteerApps() {
  const { data, error } = await db().from('volunteer_applications')
    .select('id, full_name, email, phone, network, country, payload, status, created_at')
    .in('status', ['submitted', 'under_review'])
    .order('created_at', { ascending: false }).limit(50);
  if (error) throw error;
  return data;
}
export const decideVolunteer = (vid, approve, unit, reason) =>
  appRpc('decide_volunteer', { vid, approve, unit, reason });

export const getProgrammeImpact = () => appRpc('report_programmes', {});

/* ------------------------------------------------------------------ */
/* Cases (welfare, complaints, safeguarding) — confidential            */
/* ------------------------------------------------------------------ */

const CASE_COLUMNS =
  'id, case_no, category, org_unit_id, subject, details, reporter_id, ' +
  'status, created_at, updated_at';

export async function fileCase(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('cases')
    .insert({
      category: fields.category,
      org_unit_id: fields.org_unit_id || null,
      subject: fields.subject,
      details: fields.details,
      reporter_id: session.user.id,
    })
    .select(CASE_COLUMNS).single();
  if (error) throw error;
  return data;
}

export async function listCases(opts = {}) {
  const { status = '', page = 0, pageSize = 25 } = opts;
  let q = db()
    .from('cases')
    .select(CASE_COLUMNS, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (status) q = q.eq('status', status);
  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function getCase(id) {
  const { data, error } = await db()
    .from('cases').select(CASE_COLUMNS).eq('id', id).single();
  if (error) throw error;
  return data;
}

export async function listCaseUpdates(caseId) {
  const { data, error } = await db()
    .from('case_updates')
    .select('id, note, visible_to_reporter, created_at, author_id')
    .eq('case_id', caseId)
    .order('created_at');
  if (error) throw error;
  return data;
}

export const assignCaseHandler = (caseId, handlerId) =>
  appRpc('assign_case_handler', { cid: caseId, handler: handlerId });

export const updateCaseStatus = (caseId, status, note, visible) =>
  appRpc('update_case_status',
    { cid: caseId, new_status: status, note, visible });

/* ------------------------------------------------------------------ */
/* Helpdesk                                                            */
/* ------------------------------------------------------------------ */

const TICKET_COLUMNS =
  'id, ticket_no, category, priority, subject, details, requester_id, ' +
  'assigned_to, status, resolved_at, created_at, updated_at';

export async function fileTicket(fields) {
  const session = await getSession();
  const { data, error } = await db()
    .from('tickets')
    .insert({
      category: fields.category,
      priority: fields.priority,
      subject: fields.subject,
      details: fields.details,
      requester_id: session.user.id,
    })
    .select(TICKET_COLUMNS).single();
  if (error) throw error;
  return data;
}

export async function listTickets(opts = {}) {
  const { status = '', page = 0, pageSize = 25 } = opts;
  let q = db()
    .from('tickets')
    .select(TICKET_COLUMNS, { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(page * pageSize, page * pageSize + pageSize - 1);
  if (status) q = q.eq('status', status);
  const { data, error, count } = await q;
  if (error) throw error;
  return { rows: data, total: count ?? 0 };
}

export async function getTicket(id) {
  const { data, error } = await db()
    .from('tickets').select(TICKET_COLUMNS).eq('id', id).single();
  if (error) throw error;
  return data;
}

export async function listTicketMessages(ticketId) {
  const { data, error } = await db()
    .from('ticket_messages')
    .select('id, author_id, body, created_at')
    .eq('ticket_id', ticketId)
    .order('created_at');
  if (error) throw error;
  return data;
}

export async function addTicketMessage(ticketId, body) {
  const session = await getSession();
  const { error } = await db()
    .from('ticket_messages')
    .insert({ ticket_id: ticketId, author_id: session.user.id, body });
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Staff messages (HQ)                                                 */
/* ------------------------------------------------------------------ */

export async function listStaffMessages() {
  const session = await getSession();
  const me = session.user.id;
  const { data, error } = await db()
    .from('staff_messages')
    .select('id, sender_id, recipient_id, body, read_at, created_at, ' +
      'attachment_path, attachment_name')
    .or(`sender_id.eq.${me},recipient_id.eq.${me}`)
    .order('created_at', { ascending: false })
    .limit(50);
  if (error) throw error;
  return { rows: data, myId: me };
}

export async function sendStaffMessage(recipientId, body, file = null) {
  const session = await getSession();
  let attachment_path = null;
  let attachment_name = null;
  if (file) {
    attachment_path = `${session.user.id}/${crypto.randomUUID()}`;
    attachment_name = file.name.slice(0, 200);
    const { error: upErr } = await db().storage
      .from('staff-files')
      .upload(attachment_path, file, {
        contentType: file.type || 'application/octet-stream',
      });
    if (upErr) throw upErr;
  }
  const { error } = await db()
    .from('staff_messages')
    .insert({ sender_id: session.user.id, recipient_id: recipientId,
      body, attachment_path, attachment_name });
  if (error) throw error;
}

export async function staffFileUrl(path) {
  const { data, error } = await db().storage.from('staff-files')
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}


/** Server-computed labels for everyone I share messages with.
 *  Members see HQ-side counterparts as 'WODDI HQ' (verified). */
export const messageIdentities = () =>
  appRpc('message_identities', {}).catch(() => []);

/** Recipient picker: HQ sees staff + field members; members see WODDI HQ. */
export const searchMessageRecipients = (s) =>
  appRpc('search_message_recipients', { s: s || '' });

/** Where a member's fresh message goes (master account first). */
export const hqInboxTarget = () =>
  appRpc('hq_inbox_target', {}).catch(() => null);

/* ------------------------------------------------------------------ */
/* 14-day activation: system verification (Phase 89)                   */
/* ------------------------------------------------------------------ */

/** What the system can already verify for me (CV, module, message…). */
export const journeySignals = () =>
  appRpc('journey_signals', {}).catch(() => ({}));

/** Fire-and-forget page-visit evidence; no-ops without a live journey. */
export const logJourneyEvent = (code) =>
  appRpc('log_journey_event', { p_code: code }).catch(() => {});

/** Upload my CV to private storage and record it (system-ticked). */
export async function uploadMemberCv(file) {
  const session = await getSession();
  const path = `${session.user.id}/${crypto.randomUUID()}-`
    + String(file.name || 'cv').replaceAll('/', '_').slice(0, 120);
  const { error } = await db().storage.from('member-cvs')
    .upload(path, file, {
      contentType: file.type || 'application/octet-stream' });
  if (error) throw error;
  await appRpc('record_cv_upload', { p_path: path, p_name: file.name || 'cv' });
  return path;
}

/** HQ signed link to a member's CV. */
export async function memberCvUrl(path) {
  const { data, error } = await db().storage.from('member-cvs')
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

/** HQ-only: the org chart for one country — who holds each seat. */
export const orgChartCountry = (iso) => appRpc('org_chart_country', { iso });
export const orgChartCountries = () => appRpc('org_chart_countries', {});

/** HQ-only: everyone who passed activation and isn't yet a leader. */
export const promotionCandidates = () => appRpc('promotion_candidates', {});
export const vacantSeatsFor = (iso) => appRpc('vacant_seats_for', { iso });
export const promoteCandidate = (pid, targetUnit, targetRole) =>
  appRpc('promote_candidate',
    { pid, target_unit: targetUnit, target_role: targetRole });

/** Item 7 — nominate a leader for volunteer-spotlight recognition. */
export const submitSpotlightNomination = (fields) =>
  appRpc('submit_spotlight_nomination', {
    p_category: fields.category, p_nominee: fields.nomineeId,
    p_contribution: fields.contribution, p_evidence: fields.evidence,
    p_period_start: fields.periodStart || null,
    p_period_end: fields.periodEnd || null,
    p_other_contributors: fields.otherContributors || '',
    p_mission_note: fields.missionNote || '' });

/** HQ-only: the established leadership atlas. */
export const leadersAtlas = () => appRpc('leaders_atlas', {});

/** Phase 108 — end or reactivate a leader's seat, with the leader
 *  notified (notice + email) as the UAT committee required. */
/** Phase 111 — network volunteer registration via RPC so the success
 *  screen can state the reference number and network track. */
export const submitVolunteerReg = ({ fullName, email, phone, network,
  country, about }) =>
  appRpc('submit_volunteer_reg', {
    p_full_name: fullName, p_email: email, p_phone: phone,
    p_network: network, p_country: country, p_about: about });

export const setLeaderAppointment = (assignmentId, action, reason) =>
  appRpc('set_leader_appointment',
    { p_assignment: assignmentId, p_action: action, p_reason: reason });

/** HQ-only: the 14-day activation accountability table. */
export const activationReport = () => appRpc('activation_report', {});

/** HQ-only: one candidate's full day-by-day report + recommendation —
 *  only meaningful once her journey has actually concluded. */
export const activationIndividualReport = (journeyId) =>
  appRpc('activation_individual_report', { jid: journeyId });

export async function markMessageRead(id) {
  const { error } = await db()
    .from('staff_messages')
    .update({ read_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}

/** HQ root unit id (for staff tasks and HQ meetings). */
export async function getHqUnitId() {
  const { data, error } = await db()
    .from('org_units').select('id').eq('level', 'headquarters').single();
  if (error) throw error;
  return data.id;
}

/* ------------------------------------------------------------------ */
/* Documents                                                           */
/* ------------------------------------------------------------------ */

export async function listDocFolders(parentId) {
  let q = db().from('doc_folders')
    .select('id, name, parent_id, org_unit_id')
    .order('name');
  q = parentId ? q.eq('parent_id', parentId) : q.is('parent_id', null);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function createDocFolder(fields) {
  const session = await getSession();
  const { error } = await db().from('doc_folders').insert({
    name: fields.name, parent_id: fields.parent_id,
    org_unit_id: fields.org_unit_id, created_by: session.user.id });
  if (error) throw error;
}

export async function listDocuments(folderId, includeArchived) {
  let q = db().from('documents')
    .select('id, name, path, mime, archived, created_at')
    .eq('folder_id', folderId)
    .order('created_at', { ascending: false });
  if (!includeArchived) q = q.eq('archived', false);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function uploadDocument(folderId, file) {
  const session = await getSession();
  const path = crypto.randomUUID();
  const { error: upErr } = await db().storage.from('documents')
    .upload(path, file, {
      contentType: file.type || 'application/octet-stream' });
  if (upErr) throw upErr;
  const { error } = await db().from('documents').insert({
    folder_id: folderId, name: file.name.slice(0, 200), path,
    mime: file.type || null, uploaded_by: session.user.id });
  if (error) throw error;
}

export async function setDocumentArchived(id, archived) {
  const { error } = await db().from('documents')
    .update({ archived }).eq('id', id);
  if (error) throw error;
}

export function documentUrl(path) {
  const { supabaseUrl } = getConfig();
  return `${supabaseUrl}/storage/v1/object/public/documents/${path}`;
}

/* ------------------------------------------------------------------ */
/* Global search                                                       */
/* ------------------------------------------------------------------ */

export async function globalSearch(qtext) {
  const s = qtext.replaceAll('%', '').replaceAll(',', '').trim();
  if (!s) return { members: [], tasks: [], tickets: [] };
  const like = `%${s}%`;
  const [members, tasks, tickets] = await Promise.all([
    db().from('field_members')
      .select('id, first_name, last_name, membership_no')
      .or(`first_name.ilike.${like},last_name.ilike.${like},` +
          `membership_no.ilike.${like}`)
      .limit(6).then((r) => r.data ?? []),
    db().from('tasks').select('id, title, status')
      .ilike('title', like).limit(6).then((r) => r.data ?? []),
    db().from('tickets').select('id, ticket_no, subject')
      .or(`subject.ilike.${like},ticket_no.ilike.${like}`)
      .limit(6).then((r) => r.data ?? []),
  ]);
  return { members, tasks, tickets };
}

/* ------------------------------------------------------------------ */
/* Activation journey (FRD B)                                          */
/* ------------------------------------------------------------------ */

export async function listActivationMilestones() {
  const { data, error } = await db()
    .from('activation_milestones')
    .select('id, seq, code, name, day_target, is_required, self_service')
    .eq('is_active', true)
    .order('seq');
  if (error) throw error;
  return data;
}

export async function getJourney(profileId) {
  const { data, error } = await db()
    .from('activation_journeys')
    .select('id, profile_id, status, started_at, due_at, extended_until, ' +
      'completed_at')
    .eq('profile_id', profileId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function getJourneyProgress(journeyId) {
  const { data, error } = await db()
    .from('activation_progress')
    .select('milestone_id, completed_at, note')
    .eq('journey_id', journeyId);
  if (error) throw error;
  return data;
}

export const completeMilestone = (journeyId, milestoneId, note) =>
  appRpc('complete_milestone', { jid: journeyId, mid: milestoneId,
    p_note: note || null });

export const extendActivation = (journeyId, until, reason) =>
  appRpc('extend_activation', { jid: journeyId, until, reason });

export const startActivation = (profileId) =>
  appRpc('start_activation', { pid: profileId });

/* ------------------------------------------------------------------ */
/* Activation content (Phase 33) — the 14-day curriculum & scoring     */
/* ------------------------------------------------------------------ */

export async function getActivationDays() {
  const { data, error } = await db()
    .from('activation_days')
    .select('id, day, title, kind, intro, is_gate')
    .eq('is_active', true)
    .order('day');
  if (error) throw error;
  return data;
}

export async function getActivationItems(day) {
  const { data, error } = await db()
    .from('activation_items')
    .select('id, day, seq, kind, prompt, options, points, is_required')
    .eq('day', day)
    .order('seq');
  if (error) throw error;
  return data;
}

export async function getAllActivationItems() {
  const { data, error } = await db()
    .from('activation_items')
    .select('id, day, seq, kind, prompt, options, points, is_required')
    .order('day').order('seq');
  if (error) throw error;
  return data;
}

export async function getMyResponses(journeyId) {
  const { data, error } = await db()
    .from('activation_item_responses')
    .select('item_id, answer, is_correct, score, submitted_at')
    .eq('journey_id', journeyId);
  if (error) throw error;
  return data;
}

export const submitActivationItem = (journeyId, itemId, answer) =>
  appRpc('submit_activation_item', { jid: journeyId, iid: itemId, ans: answer });

export const getActivationSummary = (journeyId) =>
  appRpc('activation_summary', { jid: journeyId });

/* ------------------------------------------------------------------ */
/* Engagement library (Phase 33) — the ongoing content rhythm          */
/* ------------------------------------------------------------------ */

export async function listEngagement(kind) {
  const { data, error } = await db()
    .from('engagement_content')
    .select('id, kind, period, title, focus, body')
    .eq('kind', kind)
    .eq('is_active', true)
    .order('period');
  if (error) throw error;
  return data;
}

export async function getEngagementFor(kind, period) {
  const { data, error } = await db()
    .from('engagement_content')
    .select('id, kind, period, title, focus, body')
    .eq('kind', kind)
    .eq('period', period)
    .eq('is_active', true)
    .maybeSingle();
  if (error) throw error;
  return data;
}

/* ------------------------------------------------------------------ */
/* Message & response library (FRD K)                                  */
/* ------------------------------------------------------------------ */

const TEMPLATE_COLUMNS =
  'id, code, locale, category, name, subject, body, status, version, ' +
  'updated_at';

export async function listMessageTemplates(category = '', locale = 'en') {
  let q = db()
    .from('message_templates')
    .select(TEMPLATE_COLUMNS)
    .eq('locale', locale)
    .order('category').order('name');
  if (category) q = q.eq('category', category);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function updateMessageTemplate(id, patch) {
  const { data, error } = await db()
    .from('message_templates')
    .update({ subject: patch.subject, body: patch.body })
    .eq('id', id)
    .select(TEMPLATE_COLUMNS).single();
  if (error) throw error;
  return data;
}

export async function approveMessageTemplate(id) {
  const { data, error } = await db()
    .from('message_templates')
    .update({ status: 'approved' })
    .eq('id', id)
    .select(TEMPLATE_COLUMNS).single();
  if (error) throw error;
  return data;
}

export async function createTemplateLocale(enTemplate, locale) {
  const { error } = await db()
    .from('message_templates')
    .insert({
      code: enTemplate.code,
      locale,
      category: enTemplate.category,
      name: enTemplate.name,
      subject: enTemplate.subject,
      body: enTemplate.body,
    });
  if (error && !String(error.message).includes('duplicate')) throw error;
}

/** Replace {tokens} with values; unknown tokens stay literal. */
export function fillTemplate(text, ctx) {
  return String(text ?? '').replace(/\{([a-z_]+)\}/g,
    (m, k) => (ctx[k] ?? m));
}

/* ------------------------------------------------------------------ */
/* Account security                                                    */
/* ------------------------------------------------------------------ */

export async function changePassword(newPassword) {
  const { error } = await db().auth.updateUser({ password: newPassword });
  if (error) throw error;
}

export async function requestPasswordReset(email) {
  return appRpc('request_password_reset', { em: email });
}

export const completePasswordReset = (tk, newpw) =>
  appRpc('complete_password_reset', { tk, newpw });

/* ------------------------------------------------------------------ */
/* Task checklists & files                                             */
/* ------------------------------------------------------------------ */

export async function listChecklist(taskId) {
  const { data, error } = await db()
    .from('task_checklist_items')
    .select('id, label, done, done_at, seq')
    .eq('task_id', taskId)
    .order('seq').order('created_at');
  if (error) throw error;
  return data;
}

export async function addChecklistItem(taskId, label) {
  const session = await getSession();
  const { error } = await db()
    .from('task_checklist_items')
    .insert({ task_id: taskId, label, created_by: session.user.id });
  if (error) throw error;
}

export async function toggleChecklistItem(id, done) {
  const session = await getSession();
  const { error } = await db()
    .from('task_checklist_items')
    .update({
      done,
      done_by: done ? session.user.id : null,
      done_at: done ? new Date().toISOString() : null,
    })
    .eq('id', id);
  if (error) throw error;
}

export async function listTaskFiles(taskId) {
  const { data, error } = await db()
    .from('task_files')
    .select('id, path, name, created_at')
    .eq('task_id', taskId)
    .order('created_at');
  if (error) throw error;
  return data;
}

export async function addTaskFile(taskId, file) {
  const session = await getSession();
  const path = crypto.randomUUID();
  const { error: upErr } = await db().storage
    .from('task-files')
    .upload(path, file, {
      contentType: file.type || 'application/octet-stream',
    });
  if (upErr) throw upErr;
  const { error } = await db()
    .from('task_files')
    .insert({ task_id: taskId, path, name: file.name.slice(0, 200),
      uploaded_by: session.user.id });
  if (error) throw error;
}

export async function taskFileUrl(path) {
  // task-files is a private bucket (migration 046): short-lived signed URLs
  const { data, error } = await db().storage.from('task-files')
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

/* ------------------------------------------------------------------ */
/* Task templates                                                      */
/* ------------------------------------------------------------------ */

export async function listTaskTemplates() {
  const { data, error } = await db()
    .from('task_templates')
    .select('id, name, title, details, priority, requires_approval, ' +
      'is_shared, created_by, tags')
    .order('name');
  if (error) throw error;
  return data;
}

export async function saveTaskTemplate(fields) {
  const session = await getSession();
  const { error } = await db()
    .from('task_templates')
    .insert({
      name: fields.name,
      title: fields.title,
      details: fields.details || null,
      tags: fields.tags || [],
      priority: fields.priority,
      requires_approval: fields.requires_approval,
      is_shared: fields.is_shared ?? false,
      created_by: session.user.id,
    });
  if (error) throw error;
}

export async function deleteTaskTemplate(id) {
  const { error } = await db()
    .from('task_templates').delete().eq('id', id);
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Task comments & mentions                                            */
/* ------------------------------------------------------------------ */

export async function listTaskComments(taskId) {
  const { data, error } = await db()
    .from('task_comments')
    .select('id, body, created_at, ' +
      'author:profiles!task_comments_author_id_fkey(first_name, last_name)')
    .eq('task_id', taskId)
    .order('created_at');
  if (error) throw error;
  return data;
}

export async function countTaskComments(taskId) {
  const { count, error } = await db()
    .from('task_comments')
    .select('id', { count: 'exact', head: true })
    .eq('task_id', taskId);
  if (error) throw error;
  return count ?? 0;
}

export async function addTaskComment(taskId, body, mentionIds = []) {
  const session = await getSession();
  const { data, error } = await db()
    .from('task_comments')
    .insert({ task_id: taskId, author_id: session.user.id, body })
    .select('id').single();
  if (error) throw error;
  if (mentionIds.length > 0) {
    const { error: mErr } = await db()
      .from('task_comment_mentions')
      .insert(mentionIds.map((pid) => ({
        comment_id: data.id, profile_id: pid })));
    if (mErr) throw mErr;
  }
}

/** People the current user may see (self, territory, staff peers, HQ). */
export async function searchMentionables(search) {
  let q = db()
    .from('profiles')
    .select('id, first_name, last_name')
    .order('first_name')
    .limit(8);
  if (search) {
    const s = search.replaceAll('%', '').replaceAll(',', '');
    q = q.or(`first_name.ilike.%${s}%,last_name.ilike.%${s}%`);
  }
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export const assignTicket = (ticketId, officerId) =>
  appRpc('assign_ticket', { tid: ticketId, officer: officerId });

export const setTicketStatus = (ticketId, status) =>
  appRpc('set_ticket_status', { tid: ticketId, new_status: status });

/* ------------------------------------------------------------------ */
/* Headquarters Operations                                             */
/* ------------------------------------------------------------------ */

export async function listDepartments() {
  const { data, error } = await db()
    .from('departments')
    .select('id, name')
    .eq('is_active', true)
    .order('name');
  if (error) throw error;
  return data;
}

export async function listStaff() {
  const { data, error } = await db()
    .from('staff')
    .select('profile_id, department_id, position_title, reports_to, ' +
      'person:profiles!staff_profile_id_fkey(id, first_name, last_name, email)')
    .eq('is_active', true)
    .order('position_title');
  if (error) throw error;
  return data;
}

export async function addStaff(fields) {
  const { error } = await db()
    .from('staff')
    .insert({
      profile_id: fields.profile_id,
      department_id: fields.department_id,
      position_title: fields.position_title,
      reports_to: fields.reports_to,
    });
  if (error) throw error;
}

const SREPORT_COLUMNS =
  'id, author_id, report_date, period, tasks_completed, tasks_in_progress, ' +
  'challenges, support_required, next_priorities, status, reviewer_id, ' +
  'reviewer_note, reviewed_at, created_at, ' +
  'author:profiles!staff_reports_author_id_fkey(id, first_name, last_name)';

export async function listStaffReports(opts = {}) {
  const { mine = false, status = '', excludeAuthor = '', pageSize = 25 } = opts;
  const session = await getSession();
  let q = db()
    .from('staff_reports')
    .select(SREPORT_COLUMNS)
    .order('report_date', { ascending: false })
    .limit(pageSize);
  if (mine) q = q.eq('author_id', session.user.id);
  if (status) q = q.eq('status', status);
  if (excludeAuthor) q = q.neq('author_id', excludeAuthor);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function submitStaffReport(fields) {
  const session = await getSession();
  const { error } = await db()
    .from('staff_reports')
    .insert({
      author_id: session.user.id,
      report_date: fields.report_date,
      period: fields.period,
      tasks_completed: fields.tasks_completed,
      tasks_in_progress: fields.tasks_in_progress || null,
      challenges: fields.challenges || null,
      support_required: fields.support_required || null,
      next_priorities: fields.next_priorities || null,
    });
  if (error) throw error;
}

export async function updateStaffReport(id, patch) {
  const allowed = ['tasks_completed', 'tasks_in_progress', 'challenges',
    'support_required', 'next_priorities', 'status'];
  const clean = Object.fromEntries(
    Object.entries(patch).filter(([k]) => allowed.includes(k)));
  const { data, error } = await db()
    .from('staff_reports').update(clean).eq('id', id)
    .select(SREPORT_COLUMNS).single();
  if (error) throw error;
  return data;
}

export const reviewStaffReport = (id, approve, note) =>
  appRpc('review_staff_report', { rid: id, approve, note });

/* ------------------------------------------------------------------ */
/* Avatars                                                             */
/* ------------------------------------------------------------------ */

export function avatarUrl(profileId, bust = '') {
  const { supabaseUrl } = getConfig();
  return `${supabaseUrl}/storage/v1/object/public/avatars/${profileId}` +
    (bust ? `?v=${bust}` : '');
}

export async function uploadAvatar(profileId, file) {
  const { error } = await db().storage
    .from('avatars')
    .upload(profileId, file, {
      upsert: true,
      contentType: file.type || 'image/jpeg',
      cacheControl: '300',
    });
  if (error) throw error;
}

export async function getMyDay() {
  const session = await getSession();
  const me = session.user.id;
  const today = new Date().toISOString().slice(0, 10);
  const weekAhead = new Date(Date.now() + 7 * 864e5).toISOString();
  const nowIso = new Date().toISOString();

  const head = (table, build) => {
    // Count with '*': announcement_reads has no 'id' column, and head
    // counts never fetch data anyway.
    let q = db().from(table).select('*', { count: 'exact', head: true });
    return build(q).then(({ count, error }) => {
      if (error) throw error;
      return count ?? 0;
    });
  };

  const [myOpen, myOverdue, reviewQueue, openApps, meetingsWeek,
    annTotal, annRead] = await Promise.all([
    head('tasks', (q) => q.eq('assigned_to', me)
      .in('status', ['not_started', 'in_progress'])),
    head('tasks', (q) => q.eq('assigned_to', me)
      .in('status', ['not_started', 'in_progress', 'awaiting_review'])
      .not('due_on', 'is', null).lt('due_on', today)),
    head('tasks', (q) => q.eq('status', 'awaiting_review')
      .neq('assigned_to', me)),
    head('applications', (q) => q.in('status',
      ['submitted', 'under_review', 'recommended'])),
    head('meetings', (q) => q.eq('status', 'scheduled')
      .gte('starts_at', nowIso).lte('starts_at', weekAhead)),
    head('announcements', (q) => q),
    head('announcement_reads', (q) => q.eq('profile_id', me)),
  ]);

  return {
    myOpen, myOverdue, reviewQueue, openApps, meetingsWeek,
    annUnread: Math.max(0, annTotal - annRead),
  };
}

/* ------------------------------------------------------------------ */
/* Smart automation (Phase 35)                                         */
/* ------------------------------------------------------------------ */

export async function listAutomationRules() {
  const { data, error } = await db()
    .from('automation_rules')
    .select('code, threshold_days, is_active, last_run_at, last_matches')
    .order('code');
  if (error) throw error;
  return data;
}

export async function updateAutomationRule(code, patch) {
  const { error } = await db()
    .from('automation_rules').update(patch).eq('code', code);
  if (error) throw error;
}

export async function listAutomationEvents(limit = 12) {
  const { data, error } = await db()
    .from('automation_events')
    .select('rule_code, fired_at, matches, notified')
    .order('fired_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return data;
}

export const runAutomations = () => appRpc('run_automations_guarded', {});
export const getAutomationInsights = () => appRpc('automation_insights', {});

/* ------------------------------------------------------------------ */
/* Member notices + profile self-edit (Phase 36)                       */
/* ------------------------------------------------------------------ */

export async function getMyNotices(limit = 8) {
  const { data, error } = await db()
    .from('member_notices')
    .select('id, kind, title, body, meta, created_at, read_at')
    .order('created_at', { ascending: false }).limit(limit);
  if (error) throw error;
  return data;
}

export async function markNoticeRead(id) {
  const { error } = await db()
    .from('member_notices')
    .update({ read_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}

export async function updateMyProfile(patch) {
  const { data: { session } } = await db().auth.getSession();
  const { error } = await db()
    .from('profiles').update(patch).eq('id', session.user.id);
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Courses & certification (Phase 37)                                  */
/* ------------------------------------------------------------------ */

export async function listCourses() {
  const { data, error } = await db()
    .from('courses').select('id, code, title, description')
    .eq('is_active', true).order('code');
  if (error) throw error;
  return data;
}

export async function getCourseModules(courseId) {
  const { data, error } = await db()
    .from('course_modules')
    .select('id, seq, title, lesson')
    .eq('course_id', courseId).order('seq');
  if (error) throw error;
  return data;
}

export async function getModuleQuestions(moduleId) {
  const { data, error } = await db()
    .from('course_questions')
    .select('id, seq, prompt, options')
    .eq('module_id', moduleId).order('seq');
  if (error) throw error;
  return data;
}

export async function getMyEnrollments() {
  const { data, error } = await db()
    .from('course_enrollments')
    .select('id, course_id, started_at, completed_at, cert_no');
  if (error) throw error;
  return data;
}

export async function getMyModulePasses(enrollmentId) {
  const { data, error } = await db()
    .from('course_module_passes')
    .select('module_id, score, total, passed, completed_at')
    .eq('enrollment_id', enrollmentId);
  if (error) throw error;
  return data;
}

export const enrollCourse = (courseId) =>
  appRpc('enroll_course', { cid: courseId });
export const submitCourseModule = (enrollmentId, moduleId, answers) =>
  appRpc('submit_course_module', { eid: enrollmentId, mid: moduleId, answers });
export const getCourseStats = () => appRpc('course_stats', {});
export const teamAccountability = () => appRpc('team_accountability', {});
export const peopleAnalytics = () => appRpc('people_analytics', {});
export const countryMemberStats = () => appRpc('country_member_stats', {});
export const programmeState = () => appRpc('programme_state', {});
export const getAiToken = () => appRpc('get_ai_token', {});
export const leadershipOverview = () => appRpc('leadership_overview', {});
export const setAiToken = (tok) => appRpc('set_ai_token', { tok });
export const meetingJoin = (mid) => appRpc('meeting_join', { mid });

export async function listCheckins(mid) {
  const { data, error } = await db().from('meeting_checkins')
    .select('profile_id, joined_at, profile:profiles(id, first_name, last_name, org_unit_id)')
    .eq('meeting_id', mid).order('joined_at');
  if (error) throw error;
  return data;
}

export async function uploadMeetingFile(mid, file) {
  const path = `${mid}/${crypto.randomUUID()}-${file.name.slice(0, 80)}`;
  const { error } = await db().storage.from('meeting-files')
    .upload(path, file, { upsert: false });
  if (error) throw error;
  const { error: e2 } = await db().from('meeting_files')
    .insert({ meeting_id: mid, name: file.name.slice(0, 200), path });
  if (e2) throw e2;
}

export async function listMeetingFiles(mid) {
  const { data, error } = await db().from('meeting_files')
    .select('id, name, path').eq('meeting_id', mid).order('created_at');
  if (error) throw error;
  return data;
}

export async function meetingFileUrl(path) {
  const { data, error } = await db().storage.from('meeting-files')
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

export async function saveMeetingMinutes(mid, text) {
  const { error } = await db().from('meetings')
    .update({ minutes: text.slice(0, 8000) }).eq('id', mid);
  if (error) throw error;
}

export async function msgFileUrl(path) {
  const { data, error } = await db().storage.from('staff-files')
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

export async function uploadMsgFile(file) {
  const path = `${crypto.randomUUID()}-${(file.name || 'audio.webm').slice(0, 80)}`;
  const { error } = await db().storage.from('staff-files')
    .upload(path, file, { upsert: false });
  if (error) throw error;
  return { path, name: (file.name || 'Voice message').slice(0, 200) };
}

export const announceGroupCall = (room, aud) =>
  appRpc('announce_group_call', { room, aud });

/* ------------------------------------------------------------------ */
/* Org settings (Phase 38)                                             */
/* ------------------------------------------------------------------ */

export async function getOrgSetting(key) {
  const { data, error } = await db()
    .from('org_settings').select('value').eq('key', key).maybeSingle();
  if (error) throw error;
  return data ? data.value : null;
}

export async function setOrgSetting(key, value) {
  const { error } = await db()
    .from('org_settings')
    .upsert({ key, value, updated_at: new Date().toISOString() });
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Email layer (Phase 39)                                              */
/* ------------------------------------------------------------------ */

export const setEmailSecret = (key, value) =>
  appRpc('set_email_secret', { k: key, v: value });
export const getEmailStatus = () => appRpc('get_email_status', {});

/** Phase 106 — Institute Outreach: the 46-organisation invitation list. */
export const outreachSummary = () => appRpc('outreach_summary', {});
export const sendOutreachBatch = (limit = 20) =>
  appRpc('send_outreach_batch', { p_limit: limit });
export const sendOutreachOne = (id) =>
  appRpc('send_outreach_one', { p_id: id });
export const setOutreachStatus = (id, status, newEmail) =>
  appRpc('set_outreach_status',
    { p_id: id, p_status: status, p_new_email: newEmail || null });
export const sendTestEmail = () => appRpc('send_test_email', {});

/* ------------------------------------------------------------------ */
/* Content Studio (Phase 40) — HQ curriculum editing                   */
/* ------------------------------------------------------------------ */

async function upd(table, id, patch) {
  const { error } = await db().from(table).update(patch).eq('id', id);
  if (error) throw error;
}
export const updateActivationDay = (id, patch) => upd('activation_days', id, patch);
export const updateActivationItem = (id, patch) => upd('activation_items', id, patch);
export const updateEngagement = (id, patch) => upd('engagement_content', id, patch);
export const updateCourseModule = (id, patch) => upd('course_modules', id, patch);
export const updateCourseQuestion = (id, patch) => upd('course_questions', id, patch);

export async function getActivationKeys() {          // HQ RLS gates this
  const { data, error } = await db()
    .from('activation_keys').select('item_id, correct');
  if (error) throw error;
  return data;
}
export async function setActivationKey(itemId, correct) {
  const { error } = await db().from('activation_keys')
    .upsert({ item_id: itemId, correct });
  if (error) throw error;
}
export async function getCourseKeys() {              // HQ RLS gates this
  const { data, error } = await db()
    .from('course_keys').select('question_id, correct');
  if (error) throw error;
  return data;
}
export async function setCourseKey(questionId, correct) {
  const { error } = await db().from('course_keys')
    .upsert({ question_id: questionId, correct });
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Member hygiene (Phase 41)                                           */
/* ------------------------------------------------------------------ */

export const touchLastSeen = () =>
  appRpc('touch_last_seen', {}).catch(() => {});
export const findDuplicateProfiles = () =>
  appRpc('find_duplicate_profiles', {});
export const mergeProfiles = (keep, dropId, reason) =>
  appRpc('merge_profiles', { keep, drop_id: dropId, reason });

/* ------------------------------------------------------------------ */
/* UAT feedback (Phase 43)                                             */
/* ------------------------------------------------------------------ */

export async function submitUatFeedback(row) {
  const { data, error } = await db()
    .from('uat_feedback').insert(row).select('id').single();
  if (error) throw error;
  return data.id;
}

export async function listMyUatFeedback() {
  const { data: { session } } = await db().auth.getSession();
  const { data, error } = await db()
    .from('uat_feedback').select('*')
    .eq('reporter_id', session.user.id)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

export async function listAllUatFeedback(filters = {}) {
  let q = db().from('uat_feedback').select('*')
    .order('created_at', { ascending: false }).limit(400);
  if (filters.severity) q = q.eq('severity', filters.severity);
  if (filters.status) q = q.eq('triage_status', filters.status);
  if (filters.track) q = q.eq('track', filters.track);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export async function updateUatFeedback(id, patch) {
  const { error } = await db()
    .from('uat_feedback').update(patch).eq('id', id);
  if (error) throw error;
}

export const getUatSummary = () => appRpc('uat_summary', {});

export async function uploadUatEvidence(file) {
  const { data: { session } } = await db().auth.getSession();
  const path = `${session.user.id}/${Date.now()}-${file.name.replace(/[^\w.\-]/g, '_')}`;
  const { error } = await db().storage.from('uat-evidence')
    .upload(path, file, { contentType: file.type || 'image/png' });
  if (error) throw error;
  return path;
}

export async function uatEvidenceUrl(path) {
  const { data, error } = await db().storage.from('uat-evidence')
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}

/* ------------------------------------------------------------------ */
/* Claim account (Phase 44)                                            */
/* ------------------------------------------------------------------ */

export const claimCheck = (email) => appRpc('claim_check', { em: email });

export async function claimSignUp(email, password) {
  const { data, error } = await db().auth.signUp({ email, password });
  if (error) throw error;
  return data;
}


/* Ask WODDI (Phase 46) */
export async function listMyTasksBrief() {
  const { data: { session } } = await db().auth.getSession();
  const { data, error } = await db().from('tasks')
    .select('id, title, status, due_on')
    .eq('assigned_to', session.user.id)
    .order('due_on', { ascending: true, nullsFirst: false })
    .limit(80);
  if (error) throw error;
  return data;
}


/* ------------------------------------------------------------------ */
/* Phase 131 — Volunteer Dashboard, Referrals, HQ account control     */
/* ------------------------------------------------------------------ */

/** The whole volunteer dashboard in one call. No argument = my own;
 *  a profile id = HQ "View as" (the server refuses non-HQ callers). */
export const volunteerHome = (pid) =>
  appRpc('volunteer_home', pid ? { pid } : {});

export async function submitReferral(row) {
  const { data, error } = await db().from('referrals')
    .insert({ ...row, consent: true })
    .select('id, ref_no, status, created_at').single();
  if (error) throw error;
  return data;
}

export async function listReferrals(opts = {}) {
  let q = db().from('referrals')
    .select('id, ref_no, referrer_id, category, country, state_region, lga, '
      + 'community, reason, details, status, assigned_to, hq_notes, '
      + 'org_unit_id, created_at, updated_at, '
      + 'referrer:profiles!referrals_referrer_id_fkey(first_name, last_name, email)')
    .order('created_at', { ascending: false }).limit(opts.limit || 100);
  if (opts.mine) q = q.eq('referrer_id', opts.mine);
  if (opts.status) q = q.eq('status', opts.status);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}

export const setReferralStatus = (rid, status, assignee, notes) =>
  appRpc('set_referral_status', { rid, new_status: status,
    assignee: assignee || null, notes: notes || null });

/* HQ account control (profile/role side; the server checks is_case_hq) */
export const hqAccountList = (q, lim) =>
  appRpc('hq_account_list', { q: q || '', lim: lim || 300 });
export const hqUpdateProfile = (pid, patch) =>
  appRpc('hq_update_profile', { pid, patch });
export const hqSetStatus = (pid, status) =>
  appRpc('hq_set_status', { pid, target_status: status });
export const hqSetRole = (pid, role, unit, appt = 'appointed') =>
  appRpc('hq_set_role', { pid, new_role: role, unit, appt });
export const hqSetAppointment = (pid, appt) =>
  appRpc('hq_set_appointment', { pid, appt });

/* Phase 135 — Volunteer Leadership Structure */
export const structureExplorer = (f = {}) =>
  appRpc('structure_explorer', {
    p_net: f.net || 'WGMN', p_country: f.country || null, p_state: f.state || null,
    p_level: f.level || null, p_role: f.role || null,
    p_status: f.status || 'all', p_activation: f.activation || 'all',
    p_limit: f.limit || 600 });
export async function listLevelTerms() {
  const { data, error } = await db().from('level_terms').select('*').order('country_iso');
  if (error) throw error;
  return data;
}
export async function listPositions() {
  const { data, error } = await db().from('position_master').select('*').order('seq');
  if (error) throw error;
  return data;
}
/** The eight volunteer positions, in the founder's order (fallback when offline). */
export const POSITIONS = ['country_rep', 'deputy_country_rep', 'state_coordinator',
  'assistant_state_coordinator', 'district_coordinator', 'assistant_district_coordinator',
  'cluster_coordinator', 'assistant_cluster_coordinator', 'chapter_lead', 'assistant_chapter_lead'];
export const hqEndRoles = (pid) => appRpc('hq_end_roles', { pid });
export const hqLinkDirectory = (pid, code) =>
  appRpc('hq_link_directory', { pid, code });

/** HQ account control (auth side) via the admin-users Edge Function.
 *  Actions: ping, create, set_password, set_email, ban, delete. */
export async function adminUsers(action, fields = {}) {
  const { data, error } = await db().functions.invoke('admin-users',
    { body: { action, ...fields } });
  if (error) {
    // Supabase wraps non-2xx responses; surface the function's own reason
    let detail = '';
    try {
      const ctx = error.context;
      if (ctx && typeof ctx.json === 'function') {
        const j = await ctx.json();
        detail = j?.error ? `${j.error}${j.detail ? ': ' + j.detail : ''}` : '';
      }
    } catch { /* keep generic */ }
    const e = new Error(detail || error.message || 'admin-users failed');
    e.code = detail.split(':')[0];
    throw e;
  }
  if (data && data.error) {
    const e = new Error(`${data.error}${data.detail ? ': ' + data.detail : ''}`);
    e.code = data.error;
    throw e;
  }
  return data;
}

export async function markAllAnnouncementsSeen(ids) {
  if (!ids || !ids.length) return;
  const { data: { session } } = await db().auth.getSession();
  const rows = ids.map((announcement_id) =>
    ({ announcement_id, profile_id: session.user.id }));
  await db().from('announcement_reads').upsert(rows,
    { onConflict: 'announcement_id,profile_id', ignoreDuplicates: true });
}


/* ------------------------------------------------------------------ */
/* Phase 134 — Reporting & Accountability                              */
/* ------------------------------------------------------------------ */
export const reportOpen = (tpl, onDate, meetingId, eventId) =>
  appRpc('report_open', { tpl, on_date: onDate || null, p_meeting: meetingId || null, p_event: eventId || null });
export const reportGet = (rid) => appRpc('report_get', { rid });
export const reportSave = (rid, answers, evidence, nil, nilReason) =>
  appRpc('report_save', { rid, p_answers: answers, p_evidence: evidence ?? null,
    p_nil: nil ?? null, p_nil_reason: nilReason ?? null });
export const reportValidate = (rid) => appRpc('report_validate', { rid });
export const reportSubmit = (rid) => appRpc('report_submit', { rid });
export const reportReview = (rid, decision, note, createTasks = true) =>
  appRpc('report_review', { rid, decision, note: note || null, create_tasks: createTasks });
export const reportNewVersion = (rid) => appRpc('report_new_version', { rid });
export const reportingDashboard = () => appRpc('reporting_dashboard', {});
export const reportingCompliance = (root, period, net) =>
  appRpc('reporting_compliance', { p_root: root || null, p_period: period || null, p_net: net || 'WGMN' });
export const reportingList = (scope, status, limit) =>
  appRpc('reporting_list', { scope: scope || 'mine', p_status: status || null, p_limit: limit || 100 });
export const reportingRemindersRun = () => appRpc('reporting_reminders_run', {});
export async function listReportTemplates() {
  const { data, error } = await db().from('report_templates').select('*').eq('active', true).order('code');
  if (error) throw error;
  return data;
}
export async function addActivityRecord(row) {
  const { data, error } = await db().from('activity_records').insert(row).select('id, occurred_at').single();
  if (error) throw error;
  return data;
}
export async function listActivityRecords(opts = {}) {
  let q = db().from('activity_records')
    .select('*, who:profiles!activity_records_profile_id_fkey(first_name, last_name), unit:org_units(name)')
    .order('occurred_at', { ascending: false }).limit(opts.limit || 60);
  if (opts.mine) q = q.eq('profile_id', opts.mine);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}
export async function addIssue(row) {
  const { data, error } = await db().from('issues').insert(row).select('id, issue_no').single();
  if (error) throw error;
  return data;
}
export async function listIssues(opts = {}) {
  let q = db().from('issues')
    .select('*, unit:org_units(name), who:profiles!issues_profile_id_fkey(first_name, last_name)')
    .order('severity', { ascending: false }).order('created_at', { ascending: false }).limit(opts.limit || 100);
  if (opts.open) q = q.in('status', ['open', 'in_progress', 'awaiting_decision']);
  const { data, error } = await q;
  if (error) throw error;
  return data;
}
export async function updateIssue(id, patch) {
  const { error } = await db().from('issues').update(patch).eq('id', id);
  if (error) throw error;
}
export async function uploadReportEvidence(reportId, file) {
  const safe = file.name.replace(/[^\w.\-]+/g, '_').slice(0, 80);
  const path = `${reportId}/${Date.now()}_${safe}`;
  const { error } = await db().storage.from('report-evidence').upload(path, file, { upsert: false });
  if (error) throw error;
  return { name: file.name, path, size: file.size, type: file.type };
}
export async function reportEvidenceUrl(path) {
  const { data, error } = await db().storage.from('report-evidence').createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
}
export async function addReportContribution(reportId, note, evidence = []) {
  const { error } = await db().from('report_contributions').insert({ report_id: reportId, note, evidence });
  if (error) throw error;
}
export async function getReportingConfig() {
  const { data, error } = await db().from('reporting_config').select('*');
  if (error) throw error;
  return Object.fromEntries((data || []).map((r) => [r.key, r.value]));
}
export async function setReportingConfig(key, value) {
  const { error } = await db().from('reporting_config').upsert({ key, value, updated_at: new Date().toISOString() });
  if (error) throw error;
}


/* Phase 135b — appointment acceptance + onboarding checklist */
export const acceptAppointment = () => appRpc('accept_appointment', {});
export const declineAppointment = (reason) => appRpc('decline_appointment', { reason });
export const onboardingStatus = (pid) => appRpc('onboarding_status', pid ? { pid } : {});
export const onboardingOverview = () => appRpc('onboarding_overview', {});
export async function setOnboardingStep(code, done) {
  const { data: { session } } = await db().auth.getSession();
  if (done) {
    const { error } = await db().from('onboarding_progress').upsert({ profile_id: session.user.id, step_code: code });
    if (error) throw error;
  } else {
    const { error } = await db().from('onboarding_progress').delete().eq('profile_id', session.user.id).eq('step_code', code);
    if (error) throw error;
  }
}


/* Phase 136 — referral links */
export const REF_KEY = 'wdos.ref';
export const referralVisit = (code, meta) => appRpc('referral_visit', { p_code: code, meta: meta || {} });
export const referralAttach = (code, email, visit) => appRpc('referral_attach', { p_code: code, p_email: email, p_visit: visit || null });
export const referralLinkEnsure = (f = {}) => appRpc('referral_link_ensure', {
  p_network: f.network || null, p_unit: f.unit || null, p_role: f.role || null,
  p_label: f.label || null, p_campaign: f.campaign || null, p_hq: !!f.hq });
export const referralOverview = (scope) => appRpc('referral_overview', { p_scope: scope || 'mine' });
export const referralLinkToggle = (id, active) => appRpc('referral_link_toggle', { p_id: id, p_active: active });
export function referralUrl(code) { return `${location.origin}${location.pathname}#/r/${code}`; }
export function storedReferral() {
  try {
    const r = JSON.parse(localStorage.getItem(REF_KEY) || 'null');
    if (r && Date.now() - new Date(r.at).getTime() < 30 * 86400000) return r;
  } catch { /* ignore */ }
  return null;
}
/** Called by the public doors after a successful submission: stamps the record
 *  with the referral code the device holds. Never throws. */
export async function attachStoredReferral(email) {
  const r = storedReferral();
  if (!r || !email) return;
  try { await referralAttach(r.code, email, r.visit_id || null); } catch { /* best effort */ }
}
