-- ============================================================
-- 021_fix_missing_accounts.sql
--
-- Recovery migration: Link existing profiles without accounts
-- to newly-created personal accounts.
--
-- This handles existing users who signed up BEFORE migration 017
-- made account creation mandatory. Post-017, handle_new_user auto-creates
-- accounts for new signups, but older accounts are orphaned.
--
-- Idempotent — safe to re-run (uses INSERT...ON CONFLICT).
-- ============================================================

-- Step 1: Create accounts for all profiles that don't have one.
-- The trigger on profiles.user_id → auth.users.id ensures referential
-- integrity. We infer account name from email where possible.
INSERT INTO accounts (id, owner_user_id, name, created_at, updated_at)
SELECT
  gen_random_uuid(),
  p.user_id,
  COALESCE(p.full_name, SPLIT_PART(u.email, '@', 1)) || '''s Account',
  NOW(),
  NOW()
FROM profiles p
JOIN auth.users u ON u.id = p.user_id
WHERE p.account_id IS NULL
ON CONFLICT (owner_user_id) DO NOTHING;

-- Step 2: Link profiles to their new accounts.
UPDATE profiles p
SET
  account_id = a.id,
  account_role = 'owner'
FROM accounts a
WHERE p.user_id = a.owner_user_id
  AND p.account_id IS NULL;

-- Step 3: Verify no profiles are orphaned.
-- This should return 0 rows; if it doesn't, investigate the accounts
-- table for duplicate owner_user_id rows (shouldn't happen due to the
-- unique index created in 017).
SELECT COUNT(*) as orphaned_profiles
FROM profiles
WHERE account_id IS NULL;
