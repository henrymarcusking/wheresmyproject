-- =====================================================================
--  WheresMy — Packing Lists setup
--  Run in the Supabase SQL Editor (after the auth/RLS setup).
--  Safe to re-run.
--
--  NOTE: assumes items.id is a bigint (the app's default). If your items.id
--  is a uuid, change "item_id bigint" below to "item_id uuid".
-- =====================================================================

-- 1. Lists
create table if not exists packing_lists (
    id           uuid primary key default gen_random_uuid(),
    name         text not null,
    owner        text,
    sort_order   int,
    household_id uuid not null default auth_household_id() references households(id) on delete cascade,
    created_at   timestamptz not null default now()
);

-- 2. Items on a list, with a per-item "packed" flag
create table if not exists packing_list_items (
    id           uuid primary key default gen_random_uuid(),
    list_id      uuid   not null references packing_lists(id) on delete cascade,
    item_id      bigint not null references items(id) on delete cascade,
    packed       boolean not null default false,
    household_id uuid not null default auth_household_id() references households(id) on delete cascade,
    created_at   timestamptz not null default now(),
    unique (list_id, item_id)
);

-- 3. RLS — only members of the household can see/change its lists
alter table packing_lists      enable row level security;
alter table packing_list_items enable row level security;

drop policy if exists "household full access" on packing_lists;
drop policy if exists "household full access" on packing_list_items;

create policy "household full access" on packing_lists
    for all using (household_id = auth_household_id())
    with check (household_id = auth_household_id());

create policy "household full access" on packing_list_items
    for all using (household_id = auth_household_id())
    with check (household_id = auth_household_id());
