-- זמן בכיף — "מגירה" למשימות בתוך אותו פרויקט Supabase של כסף בכיף.
-- משתמש במשפחות, בחברים ובתפקידים (הורה/ילד) שכבר קיימים. לא נוגע בטבלאות של התקציב.

create table if not exists zman_items (
  household_id uuid references households(id) on delete cascade,
  id text not null,
  data jsonb not null,
  deleted boolean not null default false,
  created_by uuid default auth.uid(),
  assignee uuid,                      -- בשביל מי (אם יש לו חשבון)
  private boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (household_id, id)
);
create index if not exists zman_items_updated on zman_items (household_id, updated_at);

drop trigger if exists zman_items_touch on zman_items;
create trigger zman_items_touch before insert or update on zman_items for each row execute function touch_updated();

alter table zman_items enable row level security;

-- מי רואה משימה: מי שרשם, מי שהיא בשבילו, וכל ההורים — אלא אם היא פרטית
create or replace function zman_can_see(h uuid, creator uuid, assigned uuid, priv boolean) returns boolean
language sql security definer stable set search_path = public as $$
  select is_member(h) and (creator = auth.uid() or assigned = auth.uid() or (not priv and is_parent(h)));
$$;

drop policy if exists "zman select" on zman_items;
drop policy if exists "zman insert" on zman_items;
drop policy if exists "zman update" on zman_items;
drop policy if exists "zman delete" on zman_items;
create policy "zman select" on zman_items for select using (zman_can_see(household_id, created_by, assignee, private));
create policy "zman insert" on zman_items for insert with check (is_member(household_id) and created_by = auth.uid());
create policy "zman update" on zman_items for update
  using (zman_can_see(household_id, created_by, assignee, private))
  with check (zman_can_see(household_id, created_by, assignee, private));
create policy "zman delete" on zman_items for delete using (is_member(household_id) and created_by = auth.uid());

-- עדכונים בזמן אמת בין הטלפונים
do $$ begin
  begin alter publication supabase_realtime add table zman_items; exception when others then null; end;
end $$;

-- זמנים תפוסים של משימות פרטיות של בני הבית — רק "מתי", בלי "מה" (בשביל התראות על התנגשויות). רק להורים.
create or replace function zman_busy(h uuid)
returns table (id text, created_by uuid, assignee uuid, for_p text, due text, dur int)
language sql security definer stable set search_path = public as $$
  select z.id, z.created_by, z.assignee, z.data->>'forP', z.data->>'due', coalesce((z.data->>'dur')::int, 0)
  from zman_items z
  where z.household_id = h and is_parent(h) and z.private and not z.deleted
    and z.data->>'status' = 'open' and z.data->>'due' is not null and coalesce(z.data->>'hasTime', 'false') = 'true'
    and z.created_by <> auth.uid();
$$;
revoke all on function zman_busy(uuid) from public, anon;
grant execute on function zman_busy(uuid) to authenticated;
