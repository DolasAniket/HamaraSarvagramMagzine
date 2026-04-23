# 🌾 Hamara SarvaGram — Internal Magazine Platform

A mobile-first internal magazine for SarvaGram's 5 zones: Gujarat, Karnataka, Maharashtra, Rajasthan, Telangana.

**Version 2.0 — security-hardened.** This release replaces the frontend-only admin password with a real server-side authentication model and locks down Supabase Row-Level Security. If you are upgrading from v1.0, **read the "Upgrading from v1.0" section below before deploying.**

---

## 📁 Project Files

```
hamara-sarvagram/
├── index.html       ← Magazine homepage (public)
├── submit.html      ← Submission form (public)
├── mysubs.html      ← Track my submissions (public)
├── admin.html       ← Admin panel (token-authenticated)
├── supabase.js      ← Database + auth layer (shared)
├── schema.sql       ← Database schema + security policies — run once
├── AUDIT_REPORT.md  ← Security audit and change log
└── README.md        ← This file
```

---

## 🚀 Fresh Install

### Step 1 — Create Supabase project

1. Sign up at [supabase.com](https://supabase.com) → **New Project** → region `Mumbai` or `Singapore`
2. Wait ~2 minutes for provisioning

### Step 2 — Run the schema

1. Supabase dashboard → **SQL Editor** → **New Query**
2. Paste the entire contents of `schema.sql` → **Run**
3. You should see `Success. No rows returned`

### Step 3 — Set the admin password

The admin password is now stored as a bcrypt hash in the database, **not in any file**. Set it from the Supabase SQL editor:

```sql
insert into admin_credentials (id, password_hash)
  values (1, crypt('YOUR_STRONG_PASSWORD_HERE', gen_salt('bf', 10)))
on conflict (id) do update
  set password_hash = excluded.password_hash, updated_at = now();
```

Replace `YOUR_STRONG_PASSWORD_HERE` with a strong password (16+ characters, mixed). **Do not use weak/guessable passwords.** There is no "forgot password" — if you lose it, run the same statement again with a new password.

### Step 4 — Get your API keys

Supabase dashboard → **Settings → API**. Copy:
- **Project URL** (`https://xxxxx.supabase.co`)
- **anon public** key

### Step 5 — Update `supabase.js`

Open `supabase.js` and set:

```javascript
const SUPABASE_URL      = 'https://xxxxx.supabase.co';   // Your Project URL
const SUPABASE_ANON_KEY = 'sb_publishable_...';          // Your anon key
```

Note: `ADMIN_PASSWORD` is **no longer** in this file. This is intentional — the password lives only in the database and never touches any JS file.

### Step 6 — (Optional) Photo storage

Supabase dashboard → **Storage → New Bucket** → name: `photos`, set to Public.

### Step 7 — Deploy

**Option A — GitHub Pages (recommended, free):**
1. Push to a GitHub repo
2. Settings → Pages → Source → `main` branch → Save
3. URL: `https://yourusername.github.io/your-repo-name/`

**Option B — Netlify drop:**
Drag the folder to [netlify.com/drop](https://netlify.com/drop).

### Step 8 — Verify

1. Open the deployed site → you should see the magazine homepage with demo data
2. Submit a test thought via `/submit.html`
3. Open `/admin.html` → sign in with the password you set in Step 3
4. Your test submission should appear in Review → Approve → Publish
5. Refresh homepage → your post should be live

---

## 🔄 Upgrading from v1.0

If you are running the first-generation code (the one with `ADMIN_PASSWORD` in `supabase.js`), **stop**. That system has multiple critical vulnerabilities documented in `AUDIT_REPORT.md`. Upgrade in this exact order:

### Step 1 — Snapshot your database (safety first)

Supabase dashboard → Project Settings → Database → Backups → Manual snapshot. Wait for it to complete before proceeding.

### Step 2 — Run the new `schema.sql`

The script is idempotent — re-running it is safe. It will:
- Add new tables (`admin_sessions`, `admin_credentials`, `audit_log`)
- Add new RPCs (`admin_login`, `admin_publish_submission`, `admin_unpublish_submission`, `is_admin`, `admin_logout`)
- Add new constraints (length checks, unique index)
- **Replace all old RLS policies** with token-based ones
- Install the submission rate-limit trigger

Any content in your existing `submissions`, `published_content`, or `birthdays` tables is preserved.

### Step 3 — Set the admin password (Step 3 above)

### Step 4 — Replace frontend files

Overwrite these files with the v2.0 versions:
- `index.html`
- `admin.html`
- `submit.html`
- `mysubs.html`
- `supabase.js`

Keep your existing `supabase.js` `SUPABASE_URL` and `SUPABASE_ANON_KEY` values — just paste them into the new file.

### Step 5 — Rotate your Supabase anon key

Supabase dashboard → Settings → API → **Regenerate anon key**. The old one was exposed in your v1.0 code and in Git history; treat it as compromised. Paste the new key into `supabase.js`.

### Step 6 — Redeploy

Push to GitHub (or re-drag to Netlify).

### Step 7 — Clear existing admin sessions (belt-and-braces)

In Supabase SQL editor:

```sql
delete from admin_sessions;
```

Any admin who had the old login gets booted. They'll need to sign in again.

### Step 8 — Verify the fix

1. Open DevTools → Console → run:
   ```javascript
   fetch('https://<your-project>.supabase.co/rest/v1/submissions?id=eq.00000000-0000-0000-0000-000000000000', {
     method:'PATCH',
     headers:{apikey:'<your-anon-key>', Authorization:'Bearer <your-anon-key>', 'Content-Type':'application/json'},
     body: JSON.stringify({status:'rejected'})
   }).then(r => console.log('Status:', r.status));
   ```
2. Expected: HTTP `401` or `403` (request denied by RLS).
3. If you see `200` or `204`, something is wrong with the RLS policies — recheck `schema.sql` ran completely.

---

## 🔐 Admin Access

- Admin panel: `yoursite.com/admin.html`
- Password: set via SQL (Step 3). **Nowhere else.**
- The admin panel is not linked from the public nav. (The homepage footer has no admin link anymore.)
- Session duration: 8 hours. After that, the admin is automatically redirected to sign in again.

### Changing the admin password

Run the same SQL insert from Step 3 with a new password. To force all existing sessions to expire immediately, also run `delete from admin_sessions;`.

### Multiple admins

Today, there is one admin password shared by the editorial team. To give each zone editor their own login (Phase 5), extend `admin_credentials` with an `id`, `label`, and `scope_zone`, and change `admin_login()` to accept a username as well. See `AUDIT_REPORT.md` section 9.5 for the full pattern.

---

## 📋 Admin Workflow

```
Employee submits → Status: pending (rate-limited: 5/hour/emp_id)
        ↓
Admin reviews in admin.html → Approve / Reject
        ↓
Admin picks section + priority → Publish (atomic via RPC)
        ↓
Status: published, and a published_content row is created
        ↓
Magazine homepage reflects the change immediately on next load
```

**Priority scale:** 1 = highest (shown first), 3 = standard, 5 = lowest.

**Unpublish** returns the submission to `approved` status and deactivates the live row. The post is never deleted — re-publishing a second time updates the existing row rather than creating a duplicate (prevents ghost posts).

---

## 🗄️ What changed vs. v1.0

| Area | v1.0 | v2.0 |
|---|---|---|
| Admin password | Plaintext string in `supabase.js` | bcrypt hash in DB, never in any file |
| Admin auth | Client-side `===` comparison | Server RPC → token → header-validated on every request |
| RLS on submissions | `using (true)` (wide open) | `is_admin()` for writes/reads-all |
| RLS on published_content | `using (true)` for writes | `is_admin()` for writes |
| Publish / unpublish | Two separate REST calls (non-atomic) | Single RPC call (atomic) |
| Re-publish | Creates duplicate rows | Upsert-style (no duplicates) |
| Submission rate limit | None | 5 per hour per emp_id (DB trigger) |
| Zone='all' in zone views | Hidden | Shown (company-wide posts visible everywhere) |
| Data fetching | Single query for all published | Per-section with limits (O(1) at 5000+ posts) |
| Input length | UI-only hint | DB check constraints + client guards |
| CSV export | Formula-injection vulnerable | Leading `=+-@` chars escaped |
| Hero auto-rotate | Stacks intervals on zone switch (CPU hog) | Single interval, cleared & re-created per rebuild |
| XSS via image URL | `esc()` only, attribute-break possible | `safeImgUrl()` + `escAttr()`, rejects non-http(s) |
| Audit trail | None | Every admin action logged to `audit_log` |

---

## 💰 Cost

| Service | Cost |
|---|---|
| GitHub Pages hosting | Free forever |
| Supabase free tier (500 MB DB, 1 GB storage, 500 K DB reads/mo) | Free forever |
| **Total** | **₹0 / month** |

At 50–100 posts/month this fits comfortably. Expect the free tier to cover you up to ~10,000 active employees.

---

## 🆘 Troubleshooting

**Admin login says "Invalid password" even with correct password.**
→ Did you run Step 3 (the `insert into admin_credentials` statement) in the Supabase SQL editor? The DB must have a row in `admin_credentials` with id = 1.

**Admin login works, but approve/publish fails with 401.**
→ Your browser's session token has expired (8-hour default). Sign out, sign in again.

**Submissions fail with "Rate limit" error.**
→ The same employee tried to submit 5+ times in the past hour. Wait an hour, or lower the limit in `fn_submission_rate_limit()` if needed.

**Homepage is blank.**
→ Demo data should always show. Check browser console for JS errors. Most likely cause: `supabase.js` has the wrong `SUPABASE_URL` or key (demo mode doesn't break rendering, but a typo in the URL will).

**I see 403 on every published_content read in the console.**
→ RLS policies were replaced but `is_active = true` rows are correctly public-readable. Open a specific row with `https://<project>.supabase.co/rest/v1/published_content?is_active=eq.true&limit=1` — should return data. If 403, re-run `schema.sql`.

**I just forgot the admin password.**
→ Run Step 3 again with a new password. No recovery needed — there's no email flow, the DB is ground truth.

**Someone posted fake content to the magazine. How did this happen?**
→ Check `audit_log` in Supabase (`select * from audit_log order by ts desc limit 50`). The `admin_token_prefix` shows the first 8 chars of the session token used. If it doesn't match any token you issued, rotate your anon key (Settings → API → Regenerate), clear all admin sessions (`delete from admin_sessions`), and change the admin password.

---

## 📜 Security notes

This platform is exposed to the public internet on GitHub Pages. Its security relies entirely on Supabase RLS policies being correct. If you ever edit RLS policies directly in the Supabase UI, **write them back into `schema.sql`** — otherwise your next fresh-install will silently regress.

The anon key in `supabase.js` is **public by design**, like a bearer token for the gateway. It's safe because no mutation is possible without the `x-admin-token` header, which the gateway cannot forge. If you are worried about scraping, add a rate-limit at the Supabase project level (Settings → API → Rate limits).

For anything beyond internal magazine content (e.g. storing PII like phone numbers, addresses), upgrade to a real auth system (Supabase Auth + Magic Links) before rolling out.

---

*Built for SarvaGram · Hamara SarvaGram v2.0 · April 2026*
