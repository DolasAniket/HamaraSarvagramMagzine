-- ============================================================
-- HAMARA SARVAGRAM — Supabase Schema
-- Run this entire file in Supabase SQL Editor
-- ============================================================

-- ZONES
create table if not exists zones (
  id serial primary key,
  name text not null,
  slug text not null unique
);
insert into zones (name, slug) values
  ('All Zones', 'all'),
  ('Gujarat', 'gujarat'),
  ('Karnataka', 'karnataka'),
  ('Maharashtra', 'maharashtra'),
  ('Rajasthan', 'rajasthan'),
  ('Telangana', 'telangana')
on conflict do nothing;

-- SECTIONS
create table if not exists sections (
  id serial primary key,
  name text not null,
  slug text not null unique,
  max_items int default 3,
  expiry_days int default 30,
  sort_order int default 0
);
insert into sections (name, slug, max_items, expiry_days, sort_order) values
  ('Top Highlight', 'top-highlight', 1, 7, 1),
  ('What''s New', 'whats-new', 3, 14, 2),
  ('Achievements', 'achievements', 4, 30, 3),
  ('Ideas & Suggestions', 'ideas', 4, 60, 4),
  ('Employee Spotlight', 'spotlight', 2, 30, 5),
  ('On-Ground Moments', 'on-ground', 4, 30, 6),
  ('Quick Bytes', 'quick-bytes', 5, 14, 7),
  ('Zone News', 'zone-news', 6, 30, 8),
  ('Birthdays', 'birthdays', 20, 7, 9)
on conflict do nothing;

-- SUBMISSIONS
create table if not exists submissions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  emp_id text not null,
  emp_name text not null,
  zone_slug text not null references zones(slug),
  category text not null check (category in ('thought','idea','achievement','announcement','story','feedback')),
  title text not null,
  content text not null,
  extra_data jsonb default '{}',
  photo_url text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','published')),
  admin_note text,
  section_slug text references sections(slug),
  priority int default 3 check (priority between 1 and 5),
  published_at timestamptz,
  publish_issue text
);

-- PUBLISHED CONTENT (denormalised for fast reads)
create table if not exists published_content (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid references submissions(id),
  section_slug text not null references sections(slug),
  zone_slug text not null,
  priority int default 3,
  title text not null,
  content text not null,
  emp_name text,
  emp_id text,
  photo_url text,
  category text,
  extra_data jsonb default '{}',
  published_at timestamptz default now(),
  expires_at timestamptz,
  issue_label text,
  is_active boolean default true
);

-- BIRTHDAYS (auto-managed)
create table if not exists birthdays (
  id serial primary key,
  emp_name text not null,
  emp_id text not null,
  zone_slug text not null,
  role text,
  birth_date date not null
);

-- ADMIN SESSIONS (simple token auth)
create table if not exists admin_sessions (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  zone_slug text default 'all',
  role text default 'editor' check (role in ('editor','super_admin')),
  created_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '8 hours')
);

-- INDEXES
create index if not exists idx_submissions_status on submissions(status);
create index if not exists idx_submissions_zone on submissions(zone_slug);
create index if not exists idx_published_zone on published_content(zone_slug);
create index if not exists idx_published_section on published_content(section_slug);
create index if not exists idx_published_active on published_content(is_active);

-- ROW LEVEL SECURITY
alter table submissions enable row level security;
alter table published_content enable row level security;
alter table birthdays enable row level security;

-- Public can read published content
create policy "Public read published" on published_content for select using (is_active = true);
-- Public can read birthdays
create policy "Public read birthdays" on birthdays for select using (true);
-- Anyone can insert a submission
create policy "Anyone can submit" on submissions for insert with check (true);
-- Submitters can read their own by emp_id
create policy "Read own submissions" on submissions for select using (true);

-- Sample birthdays
insert into birthdays (emp_name, emp_id, zone_slug, role, birth_date) values
  ('Priya Menon', 'EMP-2217', 'maharashtra', 'Field Officer', '1990-04-20'),
  ('Anjali Tiwari', 'EMP-3301', 'maharashtra', 'Branch Lead', '1988-04-22'),
  ('Kiran Salve', 'EMP-3350', 'maharashtra', 'SarvaMitra', '1992-04-24'),
  ('Ravi Sharma', 'EMP-1100', 'gujarat', 'Field Officer', '1993-04-21'),
  ('Sunita Reddy', 'EMP-5010', 'telangana', 'Branch Manager', '1985-04-25')
on conflict do nothing;

-- Sample published content
insert into published_content (section_slug, zone_slug, priority, title, content, emp_name, emp_id, category, issue_label, expires_at) values
  ('top-highlight', 'all', 1, 'SarvaGram crosses 1.5 Lakh households', 'From the farmlands of Vidarbha to the coastal hamlets of Kochi, our SarvaMitras have woven a network that now touches over 150,000 rural families. This is not just a number — it is 150,000 dreams financed, protected, and nurtured.', 'Editorial Team', 'HQ-001', 'story', 'APR 2026', now() + interval '14 days'),
  ('whats-new', 'all', 1, 'Rabi Season Farm Loan now available across 8 zones', 'Flexible repayment aligned with harvest cycles. Apply at your nearest Shoppe. Interest rates starting at 12% per annum.', 'Loans Team', 'HQ-002', 'announcement', 'APR 2026', now() + interval '14 days'),
  ('whats-new', 'all', 2, 'Q1 Performance Awards — April 28, Pune HQ', 'All employees with outstanding performance ratings are invited. RSVP to your zone HR by April 25.', 'HR Team', 'HQ-003', 'announcement', 'APR 2026', now() + interval '14 days'),
  ('achievements', 'all', 1, 'Zero NPA for Q1 2026 — Bhopal Zone', 'Quarter after quarter, Sunil Yadav''s branch has set the standard. 12 officers, zero defaults, 100% on-time repayments.', 'Sunil Yadav', 'EMP-1180', 'achievement', 'APR 2026', now() + interval '30 days'),
  ('achievements', 'maharashtra', 2, 'Insurance Team crosses 10,000 policies milestone', 'Every family protected is a promise kept. The Pune HQ insurance team did it in a single quarter.', 'Insurance Team', 'HQ-004', 'achievement', 'APR 2026', now() + interval '30 days'),
  ('ideas', 'all', 1, 'WhatsApp loan status tracker for SarvaMitras', 'Could save field agents 30 minutes per day on status calls. Low-cost, high-impact idea submitted by Rajesh Kumar.', 'Rajesh Kumar', 'EMP-1042', 'idea', 'APR 2026', now() + interval '60 days'),
  ('spotlight', 'all', 1, 'Deepa Nair — Field Officer of the Quarter', '"Har ghar tak pahuncha — that''s not just a goal, it''s a promise I make every morning." Deepa has served 340 families in Kochi zone this quarter alone.', 'Deepa Nair', 'EMP-4471', 'story', 'APR 2026', now() + interval '30 days'),
  ('on-ground', 'maharashtra', 1, 'First mechanised harvest in Sinnar block', 'Our SarvaMitra partners in Sinnar block have transformed how farmers access equipment. Seeing a farmer smile after his first mechanised harvest — that stays with you.', 'Rajesh Kumar', 'EMP-1042', 'story', 'APR 2026', now() + interval '30 days'),
  ('on-ground', 'karnataka', 1, 'Farmer training camp — Dharwad district', '120 farmers attended a two-day training on soil health and crop rotation. Partnered with KVK Dharwad.', 'Meena Patil', 'EMP-6020', 'story', 'APR 2026', now() + interval '30 days'),
  ('quick-bytes', 'all', 1, 'Submit thoughts by 5th of each quarter month', 'All Region and Branch level inputs must reach the editorial team by the 5th for inclusion in the next issue.', 'Editorial Team', 'HQ-001', 'announcement', 'APR 2026', now() + interval '14 days'),
  ('quick-bytes', 'all', 2, 'SarvaMitra referral bonus extended till May 31', 'Refer a new SarvaMitra and earn ₹2,000 bonus. Terms apply. Contact your Zone HR for details.', 'HR Team', 'HQ-003', 'announcement', 'APR 2026', now() + interval '14 days'),
  ('quick-bytes', 'all', 3, 'Gold Loan now available in 6 zones', 'Check eligibility at your nearest Shoppe. Minimum gold weight 10 grams. Instant disbursal.', 'Loans Team', 'HQ-002', 'announcement', 'APR 2026', now() + interval '14 days'),
  ('zone-news', 'gujarat', 1, 'Gujarat zone crosses 500 active SarvaMitras', 'A big milestone for Team Gujarat! Led by Zone Head Amit Desai, the Gujarat team now has 500+ active franchise partners.', 'Amit Desai', 'EMP-7001', 'achievement', 'APR 2026', now() + interval '30 days'),
  ('zone-news', 'rajasthan', 1, 'Rajasthan team launches village savings programme', 'Working with local panchayats, our Rajasthan team has onboarded 80 self-help groups to our savings products.', 'Rekha Choudhary', 'EMP-8010', 'story', 'APR 2026', now() + interval '30 days'),
  ('zone-news', 'telangana', 1, 'Telangana zone wins National Rural Finance Award', 'Recognised at the NABARD Annual Summit for outstanding rural credit outreach in FY 2025-26.', 'Zone Team', 'EMP-9001', 'achievement', 'APR 2026', now() + interval '30 days')
on conflict do nothing;
