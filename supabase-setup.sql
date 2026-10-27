-- Apply this migration in the Supabase SQL Editor.
-- Replace all three occurrences of the placeholder with one long random sync code.
-- Enter that same code when the app prompts for its Cloud Sync Code.
-- After this succeeds, open the app, sign in as admin, and restore the JSON backup
-- from the Backup/Restore screen. The app syncs each restored section into public.kv.
-- The backup contains plaintext app passwords; rotate them after restoring.

create table if not exists public.kv (
  key text primary key,
  value jsonb,
  updated_at timestamptz not null default now()
);

alter table public.kv enable row level security;

drop policy if exists "sync_code_select" on public.kv;
drop policy if exists "sync_code_insert" on public.kv;
drop policy if exists "sync_code_update" on public.kv;

create policy "sync_code_select" on public.kv
  for select to anon, authenticated
  using (
    (current_setting('request.headers', true)::jsonb ->> 'x-sync-code') = 'REPLACE_WITH_A_LONG_RANDOM_SYNC_CODE'
  );

create policy "sync_code_insert" on public.kv
  for insert to anon, authenticated
  with check (
    (current_setting('request.headers', true)::jsonb ->> 'x-sync-code') = 'REPLACE_WITH_A_LONG_RANDOM_SYNC_CODE'
  );

create policy "sync_code_update" on public.kv
  for update to anon, authenticated
  using (
    (current_setting('request.headers', true)::jsonb ->> 'x-sync-code') = 'REPLACE_WITH_A_LONG_RANDOM_SYNC_CODE'
  )
  with check (
    (current_setting('request.headers', true)::jsonb ->> 'x-sync-code') = 'REPLACE_WITH_A_LONG_RANDOM_SYNC_CODE'
  );

grant select, insert, update on public.kv to anon, authenticated;
