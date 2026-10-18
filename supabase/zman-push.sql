-- זמן בכיף — התראות לטלפון (Web Push). רק טבלאות חדשות עם קידומת zman_. לא נוגע בטבלאות של התקציב.

-- המכשירים שביקשו התראות (טלפון/מחשב) + מה כל אחד רוצה לקבל
create table if not exists zman_push_subs (
  endpoint text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  household_id uuid references households(id) on delete cascade,
  sub jsonb not null,
  prefs jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
alter table zman_push_subs enable row level security;
drop policy if exists "zman subs own" on zman_push_subs;
create policy "zman subs own" on zman_push_subs for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- תור ההתראות: מה לשלוח, למי ומתי. השליח בענן שולח כל דקה את מה שהגיע זמנו.
create table if not exists zman_notify (
  id text primary key,
  household_id uuid not null references households(id) on delete cascade,
  to_uid uuid not null,
  at timestamptz not null,
  cat text not null,               -- msg / task / conflict / summary / shabbat
  title text not null,
  body text,
  url text,
  sent_at timestamptz,
  created_by uuid not null default auth.uid()
);
create index if not exists zman_notify_due on zman_notify (at) where sent_at is null;
alter table zman_notify enable row level security;

-- אפשר לשלוח רק לבני אותה משפחה
create or replace function zman_same_household(h uuid, target uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select is_member(h) and exists (select 1 from members where household_id = h and user_id = target);
$$;
drop policy if exists "zman notify read" on zman_notify;
drop policy if exists "zman notify write" on zman_notify;
drop policy if exists "zman notify update" on zman_notify;
drop policy if exists "zman notify delete" on zman_notify;
create policy "zman notify read" on zman_notify for select using (created_by = auth.uid() or to_uid = auth.uid());
create policy "zman notify write" on zman_notify for insert with check (created_by = auth.uid() and zman_same_household(household_id, to_uid));
create policy "zman notify update" on zman_notify for update using (created_by = auth.uid()) with check (created_by = auth.uid() and zman_same_household(household_id, to_uid));
create policy "zman notify delete" on zman_notify for delete using (created_by = auth.uid());
