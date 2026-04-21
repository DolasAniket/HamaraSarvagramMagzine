// ============================================================
// supabase.js — Hamara SarvaGram
// ============================================================
const SUPABASE_URL = 'https://ixdpsknbijcwkynolghs.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_y8omoHb5KKK_iLdD47MvYg_NknhP1to';
const ADMIN_PASSWORD = 'hamara@admin2026';
const DEMO_MODE = false;

const sb = {
  url: SUPABASE_URL,
  key: SUPABASE_ANON_KEY,
  headers(extra = {}) {
    return {
      'apikey': this.key,
      'Authorization': 'Bearer ' + this.key,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
      ...extra
    };
  },
  async select(table, params = '') {
    const r = await fetch(`${this.url}/rest/v1/${table}?${params}`, { headers: this.headers() });
    if (!r.ok) { const e = await r.json(); console.error('SELECT', table, e); throw e; }
    return r.json();
  },
  async insert(table, data) {
    const r = await fetch(`${this.url}/rest/v1/${table}`, {
      method: 'POST', headers: this.headers(), body: JSON.stringify(data)
    });
    if (!r.ok) { const e = await r.json(); console.error('INSERT', table, e); throw e; }
    const text = await r.text();
    return text ? JSON.parse(text) : [];
  },
  async update(table, data, match) {
    const params = Object.entries(match).map(([k,v]) => `${k}=eq.${encodeURIComponent(v)}`).join('&');
    const r = await fetch(`${this.url}/rest/v1/${table}?${params}`, {
      method: 'PATCH', headers: this.headers(), body: JSON.stringify(data)
    });
    if (!r.ok) { const e = await r.json(); console.error('UPDATE', table, e); throw e; }
    const text = await r.text();
    return text ? JSON.parse(text) : [];
  },
  async uploadPhoto(file) {
    const ext = file.name.split('.').pop();
    const path = `submissions/${Date.now()}.${ext}`;
    const r = await fetch(`${this.url}/storage/v1/object/photos/${path}`, {
      method: 'POST',
      headers: { 'apikey': this.key, 'Authorization': 'Bearer ' + this.key, 'Content-Type': file.type },
      body: file
    });
    if (!r.ok) return null;
    return `${this.url}/storage/v1/object/public/photos/${path}`;
  }
};

// ── PUBLIC API ─────────────────────────────────────────────
// KEY FIX: fetch ALL published content regardless of zone_slug
// Homepage JS does its own zone filtering
async function getPublished() {
  try {
    return await sb.select('published_content', 'is_active=eq.true&order=priority.asc,published_at.desc');
  } catch(e) { console.error('getPublished failed', e); return []; }
}

async function getBirthdays() {
  try {
    return await sb.select('birthdays', 'order=birth_date.asc');
  } catch(e) { return []; }
}

async function submitThought(data) {
  const payload = {
    emp_id: String(data.emp_id || '').trim(),
    emp_name: String(data.emp_name || '').trim(),
    zone_slug: data.zone_slug || 'maharashtra',
    category: data.category || 'thought',
    title: String(data.title || '').trim(),
    content: String(data.content || '').trim(),
    extra_data: data.extra_data || {},
    status: 'pending'
  };
  return sb.insert('submissions', payload);
}

async function getMySubmissions(empId) {
  try {
    return await sb.select('submissions', `emp_id=eq.${encodeURIComponent(empId.trim())}&order=created_at.desc`);
  } catch(e) { return []; }
}

// ── ADMIN API ─────────────────────────────────────────────
async function adminLogin(password) {
  if (password !== ADMIN_PASSWORD) throw new Error('Invalid password');
  sessionStorage.setItem('sg_admin_token', btoa(password + ':' + Date.now()));
  return true;
}
function adminLogout() {
  sessionStorage.removeItem('sg_admin_token');
  window.location.href = 'admin.html';
}
function checkAdmin() {
  return !!sessionStorage.getItem('sg_admin_token');
}
async function getAllSubmissions() {
  try { return await sb.select('submissions', 'order=created_at.desc'); }
  catch(e) { return []; }
}
async function updateSubmission(id, data) {
  return sb.update('submissions', data, { id });
}

// KEY FIX: publishSubmission stores the ACTUAL zone_slug from submission
// so homepage can filter correctly by zone
async function publishSubmission(submission, sectionSlug, priority) {
  const zoneSlug = submission.zone_slug || 'maharashtra';
  await sb.update('submissions', {
    status: 'published',
    section_slug: sectionSlug,
    priority: Number(priority),
    published_at: new Date().toISOString()
  }, { id: submission.id });

  await sb.insert('published_content', {
    submission_id: submission.id,
    section_slug: sectionSlug,
    zone_slug: zoneSlug,          // actual zone, not 'all'
    priority: Number(priority),
    title: submission.title,
    content: submission.content,
    emp_name: submission.emp_name || '',
    emp_id: submission.emp_id || '',
    category: submission.category,
    extra_data: submission.extra_data || {},
    is_active: true,
    published_at: new Date().toISOString(),
    issue_label: 'APR 2026',
    expires_at: new Date(Date.now() + 30 * 864e5).toISOString()
  });
  return true;
}

async function unpublishContent(id) {
  return sb.update('published_content', { is_active: false }, { id });
}

window.SG = {
  getPublished, getBirthdays, submitThought, getMySubmissions,
  getAllSubmissions, updateSubmission, publishSubmission, unpublishContent,
  adminLogin, adminLogout, checkAdmin, DEMO_MODE
};
