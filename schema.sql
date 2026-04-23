-- ============================================================
-- HAMARA SARVAGRAM — Supabase Schema (revised, security-hardened)
-- ============================================================
-- Safe to run on your EXISTING Supabase project.
-- Your existing submissions, published posts, and birthdays
-- are preserved. This script:
--   1. Cleans any legacy rows that would violate new constraints
--   2. Adds new tables (admin auth, audit log)
--   3. Creates server-side RPCs for secure admin actions
--   4. Replaces old RLS policies with token-based ones
--   5. Adds indexes and data constraints
-- ============================================================

-- ── 0. Extensions ──────────────────────────────────────────
create extension if not exists pgcrypto;

-- ── 1. Reference data ──────────────────────────────────────
create table if not exists zones (
  id serial primary key,
  name text not null,
  slug text not null unique
);
insert into zones (name, slug) values
  ('All Zones',   'all'),
  ('Gujarat',     'gujarat'),
  ('Karnataka',   'karnataka'),
  ('Maharashtra', 'maharashtra'),
  ('Rajasthan',   'rajasthan'),
  ('Telangana',   'telangana')
on conflict (slug) do nothing;

create table if not exists sections (
  id serial primary key,
  name text not null,
  slug text not null unique,
  max_items int default 3,
  expiry_days int default 30,
  sort_order int default 0
);
insert into sections (name, slug, max_items, expiry_days, sort_order) values
  ('Hero Slider',         'hero',          5,  14, 0),
  ('Top Highlight',       'top-highlight', 1,   7, 1),
  ('What''s New',         'whats-new',     3,  14, 2),
  ('Achievements',        'achievements',  4,  30, 3),
  ('Ideas & Suggestions', 'ideas',         4,  60, 4),
  ('Employee Spotlight',  'spotlight',     2,  30, 5),
  ('On-Ground Moments',   'on-ground',     4,  30, 6),
  ('Quick Bytes',         'quick-bytes',   5,  14, 7),
  ('Zone News',           'zone-news',     6,  30, 8),
  ('Birthdays',           'birthdays',    20,   7, 9)
on conflict (slug) do nothing;

-- ── 2. Submissions table ────────────────────────────────────
create table if not exists submissions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  emp_id text not null,
  emp_name text not null,
  zone_slug text not null,
  category text not null default 'thought',
  title text not null,
  content text not null,
  extra_data jsonb default '{}',
  photo_url text,
  status text not null default 'pending',
  admin_note text,
  section_slug text,
  priority int default 3,
  published_at timestamptz,
  publish_issue text
);

-- ── 3. FIX EXISTING DATA before adding constraints ─────────
-- Runs silently and fixes any legacy rows.

update submissions
set content = '[No content provided]'
where length(trim(coalesce(content, ''))) < 10;

update submissions
set content = left(content, 5000)
where length(content) > 5000;

update submissions
set title = coalesce(nullif(trim(title), ''), 'Untitled') || ''
where length(trim(coalesce(title, ''))) < 3;

update submissions
set title = left(title, 200)
where length(title) > 200;

update submissions
set emp_name = 'Unknown Employee'
where length(trim(coalesce(emp_name, ''))) < 2;

update submissions
set emp_name = left(emp_name, 100)
where length(emp_name) > 100;

update submissions
set emp_id = 'EMP-UNKNOWN'
where length(trim(coalesce(emp_id, ''))) < 3;

update submissions
set emp_id = left(emp_id, 40)
where length(emp_id) > 40;

update submissions
set status = 'pending'
where status not in ('pending', 'approved', 'rejected', 'published');

update submissions
set category = 'thought'
where category not in ('thought','idea','achievement','announcement','story','feedback');

update submissions
set priority = 3
where priority is null or priority < 1 or priority > 5;

-- ── 4. Now safely add constraints ──────────────────────────
alter table submissions drop constraint if exists chk_title_length;
alter table submissions drop constraint if exists chk_content_length;
alter table submissions drop constraint if exists chk_emp_name_length;
alter table submissions drop constraint if exists chk_emp_id_length;
alter table submissions drop constraint if exists submissions_status_check;
alter table submissions drop constraint if exists submissions_category_check;
alter table submissions drop constraint if exists submissions_priority_check;

alter table submissions
  add constraint chk_title_length
    check (char_length(title) between 3 and 200),
  add constraint chk_content_length
    check (char_length(content) between 10 and 5000),
  add constraint chk_emp_name_length
    check (char_length(emp_name) between 2 and 100),
  add constraint chk_emp_id_length
    check (char_length(emp_id) between 3 and 40),
  add constraint submissions_status_check
    check (status in ('pending','approved','rejected','published')),
  add constraint submissions_category_check
    check (category in ('thought','idea','achievement','announcement','story','feedback')),
  add constraint submissions_priority_check
    check (priority between 1 and 5);

-- ── 5. Published content ────────────────────────────────────
create table if not exists published_content (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid references submissions(id) on delete set null,
  section_slug text not null,
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

-- Fix existing published_content data
update published_content
set content = '[No content provided]'
where length(trim(coalesce(content, ''))) < 10;

update published_content
set content = left(content, 5000)
where length(content) > 5000;

update published_content
set title = 'Untitled'
where length(trim(coalesce(title, ''))) < 3;

update published_content
set title = left(title, 200)
where length(title) > 200;

alter table published_content drop constraint if exists chk_pc_title_length;
alter table published_content drop constraint if exists chk_pc_content_length;

alter table published_content
  add constraint chk_pc_title_length
    check (char_length(title) between 3 and 200),
  add constraint chk_pc_content_length
    check (char_length(content) between 10 and 5000);

drop index if exists uq_published_active_per_sub;
create unique index uq_published_active_per_sub
  on published_content(submission_id)
  where is_active = true and submission_id is not null;

-- ── 6. Birthdays ────────────────────────────────────────────
create table if not exists birthdays (
  id serial primary key,
  emp_name text not null,
  emp_id text not null,
  zone_slug text not null,
  role text,
  birth_date date not null
);

-- ── 7. Admin sessions + credentials ─────────────────────────
drop table if exists admin_sessions cascade;
create table admin_sessions (
  token text primary key,
  created_at timestamptz default now(),
  expires_at timestamptz default (now() + interval '8 hours'),
  label text
);

create table if not exists admin_credentials (
  id int primary key default 1,
  password_hash text not null,
  updated_at timestamptz default now(),
  check (id = 1)
);

-- ── 8. Audit log ────────────────────────────────────────────
create table if not exists audit_log (
  id bigserial primary key,
  ts timestamptz default now(),
  admin_token_prefix text,
  action text not null,
  target_table text,
  target_id text,
  before jsonb,
  after jsonb
);

-- ── 9. Indexes ───────────────────────────────────────────────
create index if not exists idx_submissions_status  on submissions(status);
create index if not exists idx_submissions_zone    on submissions(zone_slug);
create index if not exists idx_submissions_emp_id  on submissions(emp_id);
create index if not exists idx_submissions_created on submissions(created_at desc);
create index if not exists idx_published_zone      on published_content(zone_slug);
create index if not exists idx_published_section   on published_content(section_slug);
create index if not exists idx_published_active    on published_content(is_active) where is_active;
create index if not exists idx_published_priority  on published_content(priority, published_at desc);
create index if not exists idx_audit_ts            on audit_log(ts desc);

-- ── 10. is_admin() ───────────────────────────────────────────
create or replace function is_admin()
returns boolean
language sql
stable
security definer
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

-- ── 11. Rate limit trigger ───────────────────────────────────
create or replace function fn_submission_rate_limit()
returns trigger
language plpgsql
as $$
declare
  v_count int;
begin
  select count(*) into v_count
  from submissions
  where emp_id = new.emp_id
    and created_at > now() - interval '1 hour';
  if v_count >= 5 then
    raise exception 'Rate limit: maximum 5 submissions per hour per employee'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_submission_rate_limit on submissions;
create trigger trg_submission_rate_limit
  before insert on submissions
  for each row execute function fn_submission_rate_limit();

-- ── 12. Admin login RPC ──────────────────────────────────────
create or replace function admin_login(p_password text)
returns text
language plpgsql
security definer
as $$
declare
  v_ok    boolean;
  v_token text;
begin
  select (password_hash = crypt(p_password, password_hash))
  into v_ok
  from admin_credentials
  where id = 1;

  if not v_ok or v_ok is null then
    perform pg_sleep(0.5);
    raise exception 'invalid credentials' using errcode = '28000';
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into admin_sessions(token, label) values (v_token, 'web-admin');
  insert into audit_log(admin_token_prefix, action, target_table)
  values (substring(v_token, 1, 8), 'login', 'admin_sessions');
  return v_token;
end;
$$;

-- ── 13. Admin logout RPC ─────────────────────────────────────
create or replace function admin_logout()
returns boolean
language plpgsql
security definer
as $$
declare
  v_token text;
begin
  v_token := coalesce(
    current_setting('request.headers', true)::json->>'x-admin-token', ''
  );
  if v_token = '' then return false; end if;
  delete from admin_sessions where token = v_token;
  return true;
end;
$$;

-- ── 14. Atomic publish RPC ───────────────────────────────────
create or replace function admin_publish_submission(
  p_submission_id uuid,
  p_section_slug  text,
  p_priority      int,
  p_expires_days  int default 30
)
returns uuid
language plpgsql
security definer
as $$
declare
  v_sub   submissions;
  v_pc_id uuid;
  v_token text;
begin
  if not is_admin() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_token := coalesce(
    current_setting('request.headers', true)::json->>'x-admin-token', ''
  );
  select * into v_sub from submissions where id = p_submission_id;
  if not found then
    raise exception 'submission not found' using errcode = 'P0002';
  end if;

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
    insert into published_content (
      submission_id, section_slug, zone_slug, priority,
      title, content, emp_name, emp_id, category, extra_data,
      is_active, published_at, issue_label, expires_at
    ) values (
      p_submission_id, p_section_slug, v_sub.zone_slug, p_priority,
      v_sub.title, v_sub.content, v_sub.emp_name, v_sub.emp_id,
      v_sub.category, v_sub.extra_data,
      true, now(), to_char(now(), 'MON YYYY'),
      now() + (p_expires_days || ' days')::interval
    )
    returning id into v_pc_id;
  end if;

  update submissions
  set status       = 'published',
      section_slug = p_section_slug,
      priority     = p_priority,
      published_at = now(),
      updated_at   = now()
  where id = p_submission_id;

  insert into audit_log(admin_token_prefix, action, target_table, target_id, after)
  values (
    substring(v_token, 1, 8), 'publish', 'published_content', v_pc_id::text,
    jsonb_build_object('submission_id', p_submission_id,
                       'section_slug', p_section_slug, 'priority', p_priority)
  );
  return v_pc_id;
end;
$$;

-- ── 15. Atomic unpublish RPC ─────────────────────────────────
create or replace function admin_unpublish_submission(p_submission_id uuid)
returns boolean
language plpgsql
security definer
as $$
declare
  v_token text;
begin
  if not is_admin() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_token := coalesce(
    current_setting('request.headers', true)::json->>'x-admin-token', ''
  );
  update published_content
  set is_active = false
  where submission_id = p_submission_id and is_active = true;

  update submissions
  set status = 'approved', published_at = null, updated_at = now()
  where id = p_submission_id;

  insert into audit_log(admin_token_prefix, action, target_table, target_id)
  values (substring(v_token,1,8), 'unpublish', 'submissions', p_submission_id::text);
  return true;
end;
$$;

-- ── 16. Session cleanup ──────────────────────────────────────
create or replace function admin_session_cleanup()
returns int
language sql
security definer
as $$
  with deleted as (
    delete from admin_sessions where expires_at < now() returning 1
  )
  select count(*)::int from deleted;
$$;

-- ── 17. Row-Level Security ───────────────────────────────────
alter table submissions       enable row level security;
alter table published_content enable row level security;
alter table birthdays         enable row level security;
alter table admin_sessions    enable row level security;
alter table admin_credentials enable row level security;
alter table audit_log         enable row level security;

-- Drop every old policy by name (covers v1 and any manually added ones)
drop policy if exists "Anyone can submit"                    on submissions;
drop policy if exists "Read own submissions"                 on submissions;
drop policy if exists "submissions anon insert"              on submissions;
drop policy if exists "submissions admin all"                on submissions;
drop policy if exists "Enable insert for all"                on submissions;
drop policy if exists "Enable read access for all"           on submissions;
drop policy if exists "Enable update for all users"          on submissions;
drop policy if exists "Public read published"                on published_content;
drop policy if exists "pc public read"                       on published_content;
drop policy if exists "pc admin all"                         on published_content;
drop policy if exists "Enable read access for all"           on published_content;
drop policy if exists "Enable insert for all"                on published_content;
drop policy if exists "Enable update for all"                on published_content;
drop policy if exists "Enable update for all users"          on published_content;
drop policy if exists "Enable delete for all users"          on published_content;
drop policy if exists "Public read birthdays"                on birthdays;
drop policy if exists "bd public read"                       on birthdays;
drop policy if exists "bd admin all"                         on birthdays;

-- New policies
create policy "submissions anon insert"
  on submissions for insert to anon
  with check (status = 'pending');

create policy "submissions admin all"
  on submissions for all to anon
  using (is_admin()) with check (is_admin());

create policy "pc public read"
  on published_content for select to anon
  using (is_active = true);

create policy "pc admin all"
  on published_content for all to anon
  using (is_admin()) with check (is_admin());

create policy "bd public read"
  on birthdays for select to anon using (true);

create policy "bd admin all"
  on birthdays for all to anon
  using (is_admin()) with check (is_admin());

-- ── 18. Grants ───────────────────────────────────────────────
grant usage on schema public to anon;
grant select on zones, sections to anon;
grant select, insert, update, delete on submissions       to anon;
grant select, insert, update, delete on published_content to anon;
grant select, insert, update, delete on birthdays         to anon;

revoke all on admin_sessions    from anon;
revoke all on admin_credentials from anon;
revoke all on audit_log         from anon;

grant execute on function admin_login(text)                              to anon;
grant execute on function admin_logout()                                 to anon;
grant execute on function is_admin()                                     to anon;
grant execute on function admin_publish_submission(uuid, text, int, int) to anon;
grant execute on function admin_unpublish_submission(uuid)               to anon;
grant execute on function admin_session_cleanup()                        to anon;

-- ── 19. Sample birthday data ─────────────────────────────────
insert into birthdays (emp_name, emp_id, zone_slug, role, birth_date) values
  ('Priya Menon',   'EMP-2217', 'maharashtra', 'Field Officer',  '1990-04-20'),
  ('Anjali Tiwari', 'EMP-3301', 'maharashtra', 'Branch Lead',    '1988-04-22'),
  ('Kiran Salve',   'EMP-3350', 'maharashtra', 'SarvaMitra',     '1992-04-24'),
  ('Ravi Sharma',   'EMP-1100', 'gujarat',     'Field Officer',  '1993-04-21'),
  ('Sunita Reddy',  'EMP-5010', 'telangana',   'Branch Manager', '1985-04-25')
on conflict do nothing;

-- ============================================================
-- FINAL STEP — run this separately in a NEW query tab.
-- Replace YOUR_STRONG_PASSWORD with your actual password.
-- Delete the query after running. Do not save it.
--
-- INSERT INTO admin_credentials (id, password_hash)
-- VALUES (1, crypt('YOUR_STRONG_PASSWORD', gen_salt('bf', 10)))
-- ON CONFLICT (id) DO UPDATE
--   SET password_hash = excluded.password_hash,
--       updated_at    = now();
-- ============================================================
