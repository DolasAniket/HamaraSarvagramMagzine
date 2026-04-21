# 🌾 Hamara SarvaGram — Internal Magazine Platform

A mobile-first internal magazine platform for SarvaGram's 5 zones: Gujarat, Karnataka, Maharashtra, Rajasthan, and Telangana.

---

## 📁 Project Files

```
hamara-sarvagram/
├── index.html       ← Magazine homepage (public)
├── submit.html      ← Submission form (public)
├── mysubs.html      ← Track my submissions (public)
├── admin.html       ← Admin panel (password protected)
├── supabase.js      ← Database layer (shared)
├── schema.sql       ← Run once in Supabase to set up DB
└── README.md        ← This file
```

> **Works out of the box in DEMO MODE** — no Supabase setup needed to test. All data is local.

---

## 🚀 Option 1: Deploy to Netlify (Easiest — 60 seconds)

1. Go to [netlify.com/drop](https://netlify.com/drop)
2. Drag your entire `hamara-sarvagram` folder onto the page
3. You get a live URL like `hamara-sarvagram-abc123.netlify.app`
4. Done — share the link with your team

**To update the site later:**
- Create a free Netlify account
- Connect to the same site
- Drag the folder again to re-deploy

---

## 🚀 Option 2: Deploy to GitHub Pages (Free forever)

1. Create a free account at [github.com](https://github.com)
2. Click **New Repository** → Name it `hamara-sarvagram`
3. Upload all files (drag and drop in the GitHub UI)
4. Go to **Settings → Pages → Source → Deploy from branch → main**
5. Your URL will be: `https://yourusername.github.io/hamara-sarvagram/`

---

## 🗄️ Connect Supabase (For real data storage — free)

Without Supabase, the app runs in DEMO MODE with local data. Submissions are not saved.

### Step 1: Create Supabase project

1. Go to [supabase.com](https://supabase.com) → Sign up free
2. Click **New Project** → Name it `hamara-sarvagram`
3. Choose a password → Select region closest to India (e.g. Singapore or Mumbai)
4. Wait ~2 minutes for the project to start

### Step 2: Set up the database

1. In your Supabase dashboard → Click **SQL Editor** (left sidebar)
2. Click **New Query**
3. Open `schema.sql` from this folder → Copy all the content
4. Paste it into the SQL Editor → Click **Run**
5. You should see "Success" — your tables and demo data are created

### Step 3: Get your API keys

1. In Supabase dashboard → Go to **Settings → API**
2. Copy:
   - **Project URL** (looks like `https://xyzxyzxyz.supabase.co`)
   - **anon public** key (a long string starting with `eyJ...`)

### Step 4: Update supabase.js

Open `supabase.js` and replace these two lines at the top:

```javascript
const SUPABASE_URL = 'YOUR_SUPABASE_URL';     // ← paste Project URL here
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY'; // ← paste anon key here
```

### Step 5: Set up photo storage (optional)

1. In Supabase → Go to **Storage**
2. Click **New Bucket** → Name: `photos` → Set to **Public**
3. Photo uploads in the form will now work

### Step 6: Re-deploy

Upload the updated files to Netlify or GitHub Pages again.

---

## 🔐 Admin Access

- Admin panel is at: `yoursite.com/admin.html`
- Default password: `hamara@admin2026`
- **Change the password** in `supabase.js`:
  ```javascript
  const ADMIN_PASSWORD = 'your-new-password-here';
  ```
- The admin panel is **not linked anywhere** in the public navigation — only share the URL with editorial staff

---

## ✏️ How to Customize

### Change admin password
Edit `supabase.js` line:
```javascript
const ADMIN_PASSWORD = 'hamara@admin2026';
```

### Add/edit sections
Edit the `sections` array in `supabase.js` and also in `admin.html`

### Change magazine issue date
In `index.html`, find `Issue 04 · Q2 2026` and update

### Add more zones
In `index.html`, add a new `<button class="ztab">` in the zone tabs

### Customize section limits
In `schema.sql` or directly in Supabase → `sections` table → update `max_items`

---

## 📋 Admin Workflow

```
Employee submits → Status: PENDING
        ↓
Admin reviews in admin.html → Review panel
        ↓
Admin clicks APPROVE → Status: APPROVED
        ↓
Admin selects SECTION + PRIORITY → Clicks PUBLISH
        ↓
Status: PUBLISHED → Appears on homepage immediately
```

**Priority scale:**
- 1 = Highest (shown first)
- 2 = Medium
- 3 = Standard (default)

---

## 💰 Cost Breakdown

| Service | Cost |
|---------|------|
| Netlify hosting | Free forever |
| GitHub Pages hosting | Free forever |
| Supabase database (up to 500MB) | Free forever |
| Supabase storage (up to 1GB photos) | Free forever |
| **Total** | **₹0 / month** |

---

## 📱 Features

- ✅ Zone-based content filtering (All / Gujarat / Karnataka / Maharashtra / Rajasthan / Telangana)
- ✅ Auto-rotating flipbook hero with 5 stories
- ✅ 9 content sections (Top Highlight, What's New, Achievements, Ideas, Spotlight, On-Ground, Quick Bytes, Zone News, Birthdays)
- ✅ 6 dynamic submission form variants (Thought, Idea, Achievement, Announcement, Field Story, Feedback)
- ✅ Submission tracking by Employee ID
- ✅ Admin panel: Approve / Reject / Assign Section / Set Priority / Publish / Unpublish
- ✅ Section fill-level capacity bars
- ✅ Mobile-first responsive design
- ✅ Works offline in demo mode (no internet needed)
- ✅ Ready to deploy — no build step, no npm, no dependencies

---

## 🆘 Troubleshooting

**Submissions not saving?**
→ You're in DEMO MODE. Complete the Supabase setup above.

**Photos not uploading?**
→ Create a `photos` bucket in Supabase Storage and set it to Public.

**Admin password not working?**
→ Check `ADMIN_PASSWORD` in `supabase.js`. Must match exactly.

**Content not showing after publish?**
→ In DEMO MODE, published content appears in memory only. With Supabase connected, content is permanent.

---

*Built for SarvaGram · Hamara SarvaGram v1.0 · April 2026*
