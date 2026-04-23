-- ============================================================
-- HAMARA SARVAGRAM — COMPLETE RLS FIX
-- Paste this ENTIRE file into Supabase SQL Editor and Run.
-- Drops EVERY old policy, creates clean new ones.
-- ============================================================

-- Drop ALL submissions policies (whatever they're named)
DO $$ DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename='submissions' LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON submissions';
  END LOOP;
END $$;

-- Drop ALL published_content policies
DO $$ DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename='published_content' LOOP
    EXECUTE 'DROP POLICY IF EXISTS "' || r.policyname || '" ON published_content';
  END LOOP;
END $$;

-- SUBMISSIONS: anon insert only (status must be pending)
CREATE POLICY "sub_anon_insert"
  ON submissions FOR INSERT TO anon
  WITH CHECK (status = 'pending');

-- SUBMISSIONS: admin reads all
CREATE POLICY "sub_admin_select"
  ON submissions FOR SELECT TO anon
  USING (is_admin());

-- SUBMISSIONS: admin updates
CREATE POLICY "sub_admin_update"
  ON submissions FOR UPDATE TO anon
  USING (is_admin()) WITH CHECK (is_admin());

-- SUBMISSIONS: admin deletes
CREATE POLICY "sub_admin_delete"
  ON submissions FOR DELETE TO anon
  USING (is_admin());

-- PUBLISHED_CONTENT: public reads active; admin reads all
CREATE POLICY "pc_read"
  ON published_content FOR SELECT TO anon
  USING (is_active = true OR is_admin());

-- PUBLISHED_CONTENT: admin inserts
CREATE POLICY "pc_insert"
  ON published_content FOR INSERT TO anon
  WITH CHECK (is_admin());

-- PUBLISHED_CONTENT: admin updates
CREATE POLICY "pc_update"
  ON published_content FOR UPDATE TO anon
  USING (is_admin()) WITH CHECK (is_admin());

-- PUBLISHED_CONTENT: admin deletes
CREATE POLICY "pc_delete"
  ON published_content FOR DELETE TO anon
  USING (is_admin());

-- Verify final state
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('submissions','published_content')
ORDER BY tablename, cmd;
