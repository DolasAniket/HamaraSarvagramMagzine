// ============================================================
// supabase.js — Hamara SarvaGram (revised, security-hardened)
// ============================================================
//
// Security model:
//   - The anon key below is PUBLIC by design. It is the gateway key.
//   - All privileged actions (publish, unpublish, approve, reject, edit)
//     require an additional `x-admin-token` header whose value is only
//     obtained by calling the admin_login() Postgres RPC with the real
//     password (stored bcrypt-hashed in admin_credentials).
//   - RLS policies in schema.sql check is_admin() which reads that header.
//
// If you rotate the anon key: update SUPABASE_ANON_KEY below and redeploy.
// If someone learns the admin password: run `delete from admin_sessions;`
//   in Supabase and then reset the password via admin_credentials.
// ============================================================

const SUPABASE_URL = 'https://ixdpsknbijcwkynolghs.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_y8omoHb5KKK_iLdD47MvYg_NknhP1to';
// NOTE: ADMIN_PASSWORD is no longer stored here. The password lives only in
// admin_credentials.password_hash (bcrypt) in Supabase. This file cannot
// authenticate admins by itself — that is intentional.

const ADMIN_TOKEN_KEY = 'sg_admin_token';

// ── Session helpers ──────────────────────────────────────────
function getAdminToken() {
  return sessionStorage.getItem(ADMIN_TOKEN_KEY) || '';
}
function setAdminToken(token) {
  if (token) sessionStorage.setItem(ADMIN_TOKEN_KEY, token);
  else sessionStorage.removeItem(ADMIN_TOKEN_KEY);
}

// ── Low-level REST wrapper ──────────────────────────────────
const sb = {
  url: SUPABASE_URL,
  key: SUPABASE_ANON_KEY,

  // publicHeaders: no admin token. Used for reads and public inserts.
  publicHeaders(extra = {}) {
    return {
      apikey: this.key,
      Authorization: `Bearer ${this.key}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
      ...extra,
    };
  },

  // adminHeaders: adds x-admin-token. Used for mutations that RLS requires
  // is_admin() for. Throws immediately if no token is present — that is
  // safer than sending the request and getting a generic RLS denial.
  adminHeaders(extra = {}) {
    const token = getAdminToken();
    if (!token) throw new Error('admin session required');
    return {
      ...this.publicHeaders(extra),
      'x-admin-token': token,
    };
  },

  async select(table, params = '', opts = {}) {
    const headers = opts.admin ? this.adminHeaders() : this.publicHeaders();
    const r = await fetch(`${this.url}/rest/v1/${table}?${params}`, { headers });
    if (!r.ok) throw await this._parseError(r, 'SELECT', table);
    return r.json();
  },

  async insert(table, data, opts = {}) {
    const headers = opts.admin ? this.adminHeaders() : this.publicHeaders();
    const r = await fetch(`${this.url}/rest/v1/${table}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(data),
    });
    if (!r.ok) throw await this._parseError(r, 'INSERT', table);
    const text = await r.text();
    return text ? JSON.parse(text) : [];
  },

  async update(table, data, match, opts = {}) {
    const headers = opts.admin !== false ? this.adminHeaders() : this.publicHeaders();
    const params = Object.entries(match)
      .map(([k, v]) => `${k}=eq.${encodeURIComponent(v)}`)
      .join('&');
    const r = await fetch(`${this.url}/rest/v1/${table}?${params}`, {
      method: 'PATCH',
      headers,
      body: JSON.stringify(data),
    });
    if (!r.ok) throw await this._parseError(r, 'UPDATE', table);
    const text = await r.text();
    return text ? JSON.parse(text) : [];
  },

  async rpc(fnName, args = {}, opts = {}) {
    const headers = opts.admin ? this.adminHeaders() : this.publicHeaders();
    const r = await fetch(`${this.url}/rest/v1/rpc/${fnName}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(args),
    });
    if (!r.ok) throw await this._parseError(r, 'RPC', fnName);
    return r.json();
  },

  async _parseError(r, op, target) {
    let body;
    try {
      body = await r.json();
    } catch {
      body = { message: await r.text().catch(() => '') };
    }
    const err = new Error(body.message || `${op} ${target} failed`);
    err.status = r.status;
    err.details = body;
    // Generic 401/403 → nudge caller to re-auth
    if (r.status === 401 || r.status === 403) err.needsReauth = true;
    console.error(`[${op}] ${target}:`, err.status, body);
    return err;
  },
};

// ── PUBLIC (anonymous) API ──────────────────────────────────

/**
 * Fetch homepage content, per-section, with row limits.
 * Scales O(1) regardless of total published volume.
 *
 * @param {string} zone - 'all' | 'gujarat' | 'karnataka' | etc.
 * @returns {Promise<Object>} { 'hero': [...], 'top-highlight': [...], ... }
 */
async function getHomepage(zone = 'all') {
  const sections = [
    'hero', 'top-highlight', 'whats-new', 'achievements',
    'ideas', 'spotlight', 'on-ground', 'quick-bytes', 'zone-news',
  ];
  // For specific zones, include zone_slug='all' posts (company-wide announcements).
  // For 'all' view, return every zone.
  const zoneFilter = zone === 'all'
    ? ''
    : `&or=(zone_slug.eq.${encodeURIComponent(zone)},zone_slug.eq.all)`;

  const fetches = sections.map(async (slug) => {
    try {
      const rows = await sb.select(
        'published_content',
        `section_slug=eq.${encodeURIComponent(slug)}${zoneFilter}` +
        `&is_active=eq.true&order=priority.asc,published_at.desc&limit=10`
      );
      return [slug, rows];
    } catch (e) {
      console.warn(`getHomepage: section ${slug} failed`, e);
      return [slug, []];
    }
  });
  const results = await Promise.all(fetches);
  return Object.fromEntries(results);
}

/**
 * Legacy wrapper — returns a flat array like the old getPublished().
 * Kept for backward compatibility with index.html's current render pipeline.
 * Internally still uses the per-section call but flattens the result.
 * Prefer getHomepage() in new code.
 */
async function getPublished(zone = 'all') {
  const grouped = await getHomepage(zone);
  return Object.values(grouped).flat();
}

async function getBirthdays() {
  try {
    return await sb.select('birthdays', 'order=birth_date.asc&limit=50');
  } catch (e) {
    console.warn('getBirthdays failed', e);
    return [];
  }
}

/**
 * Submit a thought. Rate-limited server-side (5/hour/emp_id via trigger).
 * Status is forced to 'pending' by RLS policy — clients cannot self-publish.
 */
async function submitThought(data) {
  // Client-side length guards (defensive; server enforces too).
  const title = String(data.title || '').trim().slice(0, 200);
  const content = String(data.content || '').trim().slice(0, 5000);
  const emp_id = String(data.emp_id || '').trim().slice(0, 40);
  const emp_name = String(data.emp_name || '').trim().slice(0, 100);

  if (title.length < 3) throw new Error('Title must be at least 3 characters.');
  if (content.length < 10) throw new Error('Content must be at least 10 characters.');
  if (emp_id.length < 3) throw new Error('Please enter a valid Employee ID.');
  if (emp_name.length < 2) throw new Error('Please enter your full name.');

  const payload = {
    emp_id,
    emp_name,
    zone_slug: (data.zone_slug && data.zone_slug !== 'all') ? data.zone_slug : 'maharashtra',
    category: data.category || 'thought',
    title,
    content,
    extra_data: sanitizeExtra(data.extra_data || {}),
    status: 'pending', // RLS re-checks; this is advisory
  };
  return sb.insert('submissions', payload);
}

/**
 * Sanitize the extra_data JSON blob.
 * - Rejects non-http(s) URLs for known image fields.
 * - Caps total serialized size at 4KB.
 */
function sanitizeExtra(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj || {})) {
    if (v == null) continue;
    if (typeof v === 'string') {
      let s = v.slice(0, 500);
      if (/^(image_url|photo|avatar)$/i.test(k)) {
        if (!/^https?:\/\//i.test(s)) continue; // drop junk URLs
      }
      out[k] = s;
    } else if (typeof v === 'number' || typeof v === 'boolean') {
      out[k] = v;
    }
  }
  const json = JSON.stringify(out);
  if (json.length > 4096) {
    console.warn('extra_data exceeds 4KB, truncating');
    return {};
  }
  return out;
}

async function getMySubmissions(empId) {
  try {
    const id = encodeURIComponent(String(empId).trim());
    return await sb.select(
      'submissions',
      `emp_id=eq.${id}&order=created_at.desc&limit=50`
    );
  } catch (e) {
    console.warn('getMySubmissions failed', e);
    return [];
  }
}

// ── ADMIN API ───────────────────────────────────────────────

/**
 * Log in as admin. Posts password to admin_login() RPC, receives a token.
 * Token stored in sessionStorage. RPC enforces a 0.5s delay on bad password
 * to slow brute-force. Combined with pgcrypto bcrypt (cost 10), this is ~500ms
 * per attempt — practically unbrutable for any reasonable password.
 */
async function adminLogin(password) {
  if (!password) throw new Error('Password required');
  try {
    const token = await sb.rpc('admin_login', { p_password: password });
    if (typeof token !== 'string' || token.length < 32) {
      throw new Error('Invalid server response');
    }
    setAdminToken(token);
    return true;
  } catch (e) {
    setAdminToken(null);
    throw new Error('Invalid password');
  }
}

function adminLogout() {
  setAdminToken(null);
  window.location.href = 'admin.html';
}

function checkAdmin() {
  return !!getAdminToken();
}

async function getAllSubmissions() {
  try {
    return await sb.select(
      'submissions',
      'order=created_at.desc&limit=500',
      { admin: true }
    );
  } catch (e) {
    console.error('getAllSubmissions failed', e);
    throw e;
  }
}

/**
 * Admin-only: fetch all published_content rows including inactive ones.
 * Used by the Live Content / Hero panels where the admin needs to see
 * orphaned inactive rows too. Public callers should use getHomepage/getPublished.
 */
async function getAllPublished() {
  try {
    return await sb.select(
      'published_content',
      'order=priority.asc,published_at.desc&limit=500',
      { admin: true }
    );
  } catch (e) {
    console.error('getAllPublished failed', e);
    throw e;
  }
}

async function updateSubmission(id, data) {
  // Whitelist fields admin can change — never trust the caller's blob.
  const allowed = ['status', 'admin_note', 'title', 'content', 'section_slug',
                   'zone_slug', 'priority', 'published_at', 'extra_data'];
  const patch = {};
  for (const k of allowed) if (k in data) patch[k] = data[k];
  patch.updated_at = new Date().toISOString();
  return sb.update('submissions', patch, { id });
}

async function updatePublished(id, data) {
  const allowed = ['title', 'content', 'section_slug', 'zone_slug',
                   'priority', 'extra_data', 'is_active'];
  const patch = {};
  for (const k of allowed) if (k in data) patch[k] = data[k];
  return sb.update('published_content', patch, { id });
}

/**
 * Publish a submission atomically via RPC.
 * Server handles: upsert into published_content, update submission.status,
 * enforce admin auth, set expiry.
 */
async function publishSubmission(submission, sectionSlug, priority) {
  return sb.rpc('admin_publish_submission', {
    p_submission_id: submission.id,
    p_section_slug: sectionSlug,
    p_priority: Number(priority) || 3,
    p_expires_days: 30,
  }, { admin: true });
}

/**
 * Unpublish atomically. Submission status → 'approved', pc.is_active → false.
 */
async function unpublishSubmission(submissionId) {
  return sb.rpc('admin_unpublish_submission', {
    p_submission_id: submissionId,
  }, { admin: true });
}

/**
 * Legacy wrapper — some admin code removes a published_content row directly
 * (e.g. cleanup of orphaned rows). Prefer unpublishSubmission().
 */
async function unpublishContent(publishedContentId) {
  return updatePublished(publishedContentId, { is_active: false });
}

// Constants live inside window.SG below — not declared as globals.

// esc/escAttr/safeImgUrl defined inside window.SG below.

// ── Expose to window ───────────────────────────────────────
window.SG = {
  // ── Constants (defined here, not as page-level globals) ──────
  SECTIONS: [
    { slug: 'hero',          name: 'Hero Slider',    max: 5 },
    { slug: 'top-highlight', name: 'Top Highlight',  max: 1 },
    { slug: 'whats-new',     name: "What's New",     max: 3 },
    { slug: 'achievements',  name: 'Achievements',   max: 4 },
    { slug: 'ideas',         name: 'Ideas',          max: 4 },
    { slug: 'spotlight',     name: 'Spotlight',      max: 2 },
    { slug: 'on-ground',     name: 'On-Ground',      max: 4 },
    { slug: 'quick-bytes',   name: 'Quick Bytes',    max: 5 },
    { slug: 'zone-news',     name: 'Zone News',      max: 6 },
  ],
  ZONES: ['gujarat','karnataka','maharashtra','rajasthan','telangana'],
  ZONE_NAMES: {
    all:'All Zones', gujarat:'Gujarat', karnataka:'Karnataka',
    maharashtra:'Maharashtra', rajasthan:'Rajasthan', telangana:'Telangana',
  },
  CAT_LABELS: {
    thought:'Thought', idea:'Idea', achievement:'Achievement',
    announcement:'Announcement', story:'Field Story', feedback:'Feedback',
  },
  // ── Helpers ──────────────────────────────────────────────────
  esc(s){ return String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); },
  escAttr(s){ const e=this.esc(s); return e.replace(/"/g,'&quot;').replace(/'/g,'&#39;'); },
  safeImgUrl(u){ if(!u)return ''; const s=String(u).trim(); return /^https?:\/\//i.test(s)?s:''; },
  // ── Public API ───────────────────────────────────────────────
  getHomepage, getPublished, getBirthdays, submitThought, getMySubmissions,
  // ── Admin API ────────────────────────────────────────────────
  getAllSubmissions, getAllPublished, updateSubmission, updatePublished,
  publishSubmission, unpublishSubmission, unpublishContent,
  adminLogin, adminLogout, checkAdmin,
};
