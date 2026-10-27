-- Run once in Supabase SQL Editor after replacing the sync-code placeholder.
-- This copies public.kv into relational tables and leaves public.kv untouched.
-- The legacy app_users.password column is retained for compatibility with the current login.

begin;

create table if not exists public.app_settings (
  id smallint primary key default 1 check (id = 1),
  lib_name text,
  address text,
  fine_per_day numeric,
  logo text,
  auto_backup boolean,
  theme text,
  custom_categories text[] not null default '{}',
  dark_mode boolean,
  backup_time text,
  backup_folder_name text,
  card_theme jsonb,
  card_font_size text,
  card_orientation text,
  late_fee_due_day integer,
  late_fee_per_day numeric,
  late_fee_enabled boolean,
  extra jsonb not null default '{}'
);

create table if not exists public.app_users (
  id text primary key,
  name text,
  role text,
  password text,
  active boolean,
  permissions jsonb not null default '{}',
  extra jsonb not null default '{}'
);

create table if not exists public.books (
  id text primary key,
  title text,
  author text,
  accession text,
  barcode text,
  spinning text,
  shelf text,
  row_number text,
  category text,
  copies integer,
  issued integer,
  added_date text,
  needs_binding boolean,
  binding_note text,
  extra jsonb not null default '{}'
);

create table if not exists public.members (
  id text primary key,
  name text,
  father text,
  cnic text,
  mobile text,
  fee numeric,
  address text,
  join_date text,
  photo text,
  status text,
  deactivated_date text,
  fee_next_due text,
  late_fee_waived boolean,
  reactivated_date text,
  deactivated_reason text,
  extra jsonb not null default '{}'
);

create table if not exists public.issues (
  id text primary key,
  member_id text,
  book_id text,
  issue_date text,
  due_date text,
  status text,
  return_date text,
  fine numeric,
  issued_by text,
  issued_by_id text,
  received_by text,
  received_by_id text,
  extra jsonb not null default '{}'
);

create table if not exists public.fees (
  id text primary key,
  member_id text,
  month text,
  amount numeric,
  method text,
  date text,
  received_by text,
  received_by_id text,
  returned boolean,
  returned_by text,
  returned_date text,
  return_reason text,
  extra jsonb not null default '{}'
);

create table if not exists public.member_attendance (
  id text primary key,
  attendance_date text not null,
  member_id text not null,
  check_in text,
  check_out text,
  extra jsonb not null default '{}'
);

create table if not exists public.staff_attendance (
  id text primary key,
  attendance_date text not null,
  user_id text not null,
  name text,
  role text,
  check_in text,
  check_in_ts text,
  check_out text,
  check_out_ts text,
  extra jsonb not null default '{}'
);

create table if not exists public.activity_logs (
  position integer primary key,
  ts text,
  username text,
  user_id text,
  role text,
  action text,
  details text,
  extra jsonb not null default '{}'
);

create table if not exists public.expenses (
  id text primary key,
  position integer not null,
  description text,
  amount numeric,
  category text,
  date text,
  method text,
  added_by text,
  extra jsonb not null default '{}'
);

create table if not exists public.member_notes (
  id text primary key,
  position integer not null,
  note_text text,
  created_at text,
  created_by text,
  expire_date text,
  edited_at text,
  extra jsonb not null default '{}'
);

create table if not exists public.holidays (
  holiday_date text primary key,
  is_holiday boolean not null
);

create table if not exists public.app_meta (
  key text primary key,
  value jsonb not null
);

do $$
declare
  target_table text;
  sync_secret text := 'REPLACE_WITH_A_LONG_RANDOM_SYNC_CODE';
begin
  foreach target_table in array array[
    'app_settings', 'app_users', 'books', 'members', 'issues', 'fees',
    'member_attendance', 'staff_attendance', 'activity_logs', 'expenses',
    'member_notes', 'holidays', 'app_meta'
  ] loop
    execute format('alter table public.%I enable row level security', target_table);
    execute format('drop policy if exists app_sync on public.%I', target_table);
    execute format(
      'create policy app_sync on public.%I for all to anon, authenticated using ((current_setting(''request.headers'', true)::jsonb ->> ''x-sync-code'') = %L) with check ((current_setting(''request.headers'', true)::jsonb ->> ''x-sync-code'') = %L)',
      target_table, sync_secret, sync_secret
    );
    execute format('grant select, insert, update, delete on public.%I to anon, authenticated', target_table);
  end loop;
end $$;

insert into public.app_settings (
  id, lib_name, address, fine_per_day, logo, auto_backup, theme,
  custom_categories, dark_mode, backup_time, backup_folder_name,
  card_theme, card_font_size, card_orientation, late_fee_due_day,
  late_fee_per_day, late_fee_enabled, extra
)
select 1, value->>'libName', value->>'address', nullif(value->>'finePerDay','')::numeric,
  value->>'logo', nullif(value->>'autoBackup','')::boolean, value->>'theme',
  array(select jsonb_array_elements_text(coalesce(value->'customCategories','[]'::jsonb))),
  nullif(value->>'darkMode','')::boolean, value->>'backupTime', value->>'backupFolderName',
  value->'cardTheme', value->>'cardFontSize', value->>'cardOrientation',
  nullif(value->>'lateFeeDueDay','')::integer, nullif(value->>'lateFeePerDay','')::numeric,
  nullif(value->>'lateFeeEnabled','')::boolean,
  value - array['libName','address','finePerDay','logo','autoBackup','theme','customCategories','darkMode','backupTime','backupFolderName','cardTheme','cardFontSize','cardOrientation','lateFeeDueDay','lateFeePerDay','lateFeeEnabled']
from public.kv where key = 'settings'
on conflict (id) do nothing;

insert into public.app_users (id, name, role, password, active, permissions, extra)
select coalesce(item.value->>'id', item.key), item.value->>'name', item.value->>'role',
  item.value->>'pass', nullif(item.value->>'active','')::boolean,
  coalesce(item.value->'permissions','{}'::jsonb),
  item.value - array['id','name','role','pass','active','permissions']
from public.kv source cross join lateral jsonb_each(source.value) item
where source.key = 'users'
on conflict (id) do nothing;

insert into public.books (id, title, author, accession, barcode, spinning, shelf, row_number, category, copies, issued, added_date, needs_binding, binding_note, extra)
select coalesce(item.value->>'id', item.key), item.value->>'title', item.value->>'author', item.value->>'accession', item.value->>'barcode', item.value->>'spinning', item.value->>'shelf', item.value->>'row', item.value->>'category', nullif(item.value->>'copies','')::integer, nullif(item.value->>'issued','')::integer, item.value->>'addedDate', nullif(item.value->>'needsBinding','')::boolean, item.value->>'bindingNote', item.value - array['id','title','author','accession','barcode','spinning','shelf','row','category','copies','issued','addedDate','needsBinding','bindingNote']
from public.kv source cross join lateral jsonb_each(source.value) item
where source.key = 'books'
on conflict (id) do nothing;

insert into public.members (id, name, father, cnic, mobile, fee, address, join_date, photo, status, deactivated_date, fee_next_due, late_fee_waived, reactivated_date, deactivated_reason, extra)
select coalesce(item.value->>'id', item.key), item.value->>'name', item.value->>'father', item.value->>'cnic', item.value->>'mobile', nullif(item.value->>'fee','')::numeric, item.value->>'address', item.value->>'joinDate', item.value->>'photo', item.value->>'status', item.value->>'deactivatedDate', item.value->>'feeNextDue', nullif(item.value->>'lateFeeWaived','')::boolean, item.value->>'reactivatedDate', item.value->>'deactivatedReason', item.value - array['id','name','father','cnic','mobile','fee','address','joinDate','photo','status','deactivatedDate','feeNextDue','lateFeeWaived','reactivatedDate','deactivatedReason']
from public.kv source cross join lateral jsonb_each(source.value) item
where source.key = 'members'
on conflict (id) do nothing;

insert into public.issues (id, member_id, book_id, issue_date, due_date, status, return_date, fine, issued_by, issued_by_id, received_by, received_by_id, extra)
select coalesce(item.value->>'id', item.key), item.value->>'memberId', item.value->>'bookId', item.value->>'issueDate', item.value->>'dueDate', item.value->>'status', item.value->>'returnDate', nullif(item.value->>'fine','')::numeric, item.value->>'issuedBy', item.value->>'issuedById', item.value->>'receivedBy', item.value->>'receivedById', item.value - array['id','memberId','bookId','issueDate','dueDate','status','returnDate','fine','issuedBy','issuedById','receivedBy','receivedById']
from public.kv source cross join lateral jsonb_each(source.value) item
where source.key = 'issues'
on conflict (id) do nothing;

insert into public.fees (id, member_id, month, amount, method, date, received_by, received_by_id, returned, returned_by, returned_date, return_reason, extra)
select coalesce(item.value->>'id', item.key), item.value->>'memberId', item.value->>'month', nullif(item.value->>'amount','')::numeric, item.value->>'method', item.value->>'date', item.value->>'receivedBy', item.value->>'receivedById', nullif(item.value->>'returned','')::boolean, item.value->>'returnedBy', item.value->>'returnedDate', item.value->>'returnReason', item.value - array['id','memberId','month','amount','method','date','receivedBy','receivedById','returned','returnedBy','returnedDate','returnReason']
from public.kv source cross join lateral jsonb_each(source.value) item
where source.key = 'fees'
on conflict (id) do nothing;

insert into public.member_attendance (id, attendance_date, member_id, check_in, check_out, extra)
select date_item.key || '::' || member_item.key, date_item.key, member_item.key,
  member_item.value->>'checkIn', member_item.value->>'checkOut',
  case when jsonb_typeof(member_item.value) = 'object' then member_item.value - array['checkIn','checkOut'] else '{}'::jsonb end
from public.kv source cross join lateral jsonb_each(source.value) date_item
cross join lateral jsonb_each(date_item.value) member_item
where source.key = 'attendance'
on conflict (id) do nothing;

insert into public.staff_attendance (id, attendance_date, user_id, name, role, check_in, check_in_ts, check_out, check_out_ts, extra)
select date_item.key || '::' || user_item.key, date_item.key, user_item.key,
  user_item.value->>'name', user_item.value->>'role', user_item.value->>'checkIn',
  user_item.value->>'checkInTs', user_item.value->>'checkOut', user_item.value->>'checkOutTs',
  user_item.value - array['name','role','checkIn','checkInTs','checkOut','checkOutTs']
from public.kv source cross join lateral jsonb_each(source.value) date_item
cross join lateral jsonb_each(date_item.value) user_item
where source.key = 'userAtt'
on conflict (id) do nothing;

insert into public.activity_logs (position, ts, username, user_id, role, action, details, extra)
select (item.ordinality - 1)::integer, item.value->>'ts', item.value->>'user', item.value->>'userId', item.value->>'role', item.value->>'action', item.value->>'details', item.value - array['ts','user','userId','role','action','details']
from public.kv source cross join lateral jsonb_array_elements(source.value) with ordinality item(value, ordinality)
where source.key = 'actlog'
on conflict (position) do nothing;

insert into public.expenses (id, position, description, amount, category, date, method, added_by, extra)
select coalesce(item.value->>'id', 'expense-' || item.ordinality), (item.ordinality - 1)::integer, item.value->>'desc', nullif(item.value->>'amount','')::numeric, item.value->>'category', item.value->>'date', item.value->>'method', item.value->>'addedBy', item.value - array['id','desc','amount','category','date','method','addedBy']
from public.kv source cross join lateral jsonb_array_elements(source.value) with ordinality item(value, ordinality)
where source.key = 'expenses'
on conflict (id) do nothing;

insert into public.member_notes (id, position, note_text, created_at, created_by, expire_date, edited_at, extra)
select coalesce(item.value->>'id', 'note-' || item.ordinality), (item.ordinality - 1)::integer, item.value->>'text', item.value->>'createdAt', item.value->>'createdBy', item.value->>'expireDate', item.value->>'editedAt', item.value - array['id','text','createdAt','createdBy','expireDate','editedAt']
from public.kv source cross join lateral jsonb_array_elements(source.value) with ordinality item(value, ordinality)
where source.key = 'memberNotes'
on conflict (id) do nothing;

insert into public.holidays (holiday_date, is_holiday)
select item.key, item.value::text::boolean
from public.kv source cross join lateral jsonb_each(source.value) item
where source.key = 'holidays'
on conflict (holiday_date) do nothing;

insert into public.app_meta (key, value)
select key, value from public.kv
where key not in ('settings','users','books','members','issues','fees','attendance','userAtt','actlog','expenses','memberNotes','holidays')
on conflict (key) do nothing;

commit;