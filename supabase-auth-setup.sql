-- =====================================================================
--  WheresMy — Authentication + Household RLS setup
--  Run this in the Supabase SQL Editor.
--
--  DO THESE MANUAL STEPS FIRST (Dashboard, not SQL):
--    1. Authentication → Users → "Add user": create an account (email +
--       password) for you, and one for your wife. Confirm the emails.
--    2. Authentication → Providers → Email: turn OFF "Allow new users to
--       sign up" so registration is closed (you provision accounts).
--
--  THEN run sections 1–4 below. Run section 5 (the actual lockdown) LAST,
--  only after the new app version with the login screen is deployed.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Household tables + helper function
-- ---------------------------------------------------------------------

create table if not exists households (
    id          uuid primary key default gen_random_uuid(),
    name        text,
    created_at  timestamptz not null default now()
);

create table if not exists household_members (
    user_id      uuid primary key references auth.users(id) on delete cascade,
    household_id uuid not null references households(id) on delete cascade,
    created_at   timestamptz not null default now()
);

-- Returns the household_id of the currently-authenticated user.
-- SECURITY DEFINER so it can read household_members regardless of RLS
-- (this also avoids RLS recursion when policies call it).
create or replace function auth_household_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select household_id from household_members where user_id = auth.uid();
$$;


-- ---------------------------------------------------------------------
-- 2. Add household_id to the data tables, auto-stamped on insert
--    (DEFAULT means the app never has to send household_id itself)
-- ---------------------------------------------------------------------

alter table items     add column if not exists household_id uuid references households(id) default auth_household_id();
alter table locations add column if not exists household_id uuid references households(id) default auth_household_id();
alter table owners    add column if not exists household_id uuid references households(id) default auth_household_id();


-- ---------------------------------------------------------------------
-- 3. Create the household, link every existing user to it,
--    and backfill all existing rows into it.
-- ---------------------------------------------------------------------

insert into households (name)
select 'Our Home'
where not exists (select 1 from households);

-- Link all current auth users to the (single) household
insert into household_members (user_id, household_id)
select u.id, h.id
from auth.users u
cross join (select id from households order by created_at limit 1) h
on conflict (user_id) do nothing;

-- Backfill existing data rows
update items     set household_id = (select id from households order by created_at limit 1) where household_id is null;
update locations set household_id = (select id from households order by created_at limit 1) where household_id is null;
update owners    set household_id = (select id from households order by created_at limit 1) where household_id is null;


-- ---------------------------------------------------------------------
-- 4. Now that every row has a household, enforce NOT NULL
-- ---------------------------------------------------------------------

alter table items     alter column household_id set not null;
alter table locations alter column household_id set not null;
alter table owners    alter column household_id set not null;


-- =====================================================================
-- 5. THE LOCKDOWN — run this LAST (after the login-screen app is live).
--    Enables RLS so the public anon key can no longer read/write data
--    unless the request carries a logged-in user's JWT for this household.
-- =====================================================================

alter table items     enable row level security;
alter table locations enable row level security;
alter table owners    enable row level security;
alter table households        enable row level security;
alter table household_members enable row level security;

-- Data tables: a user can do anything to rows in their own household.
create policy "household full access" on items
    for all using (household_id = auth_household_id())
    with check (household_id = auth_household_id());

create policy "household full access" on locations
    for all using (household_id = auth_household_id())
    with check (household_id = auth_household_id());

create policy "household full access" on owners
    for all using (household_id = auth_household_id())
    with check (household_id = auth_household_id());

-- A user can read their own household + membership row.
create policy "read own household" on households
    for select using (id = auth_household_id());

create policy "read own membership" on household_members
    for select using (user_id = auth.uid());


-- =====================================================================
--  ADDING SOMEONE LATER (e.g. a 3rd person to the same household):
--    1. Create their account in Authentication → Users.
--    2. Run:
--         insert into household_members (user_id, household_id)
--         values ('<their-auth-user-uuid>',
--                 (select id from households order by created_at limit 1));
--
--  A SEPARATE household later: insert a new households row, then add
--  members to that one instead — RLS keeps the two lists isolated.
-- =====================================================================
