-- =============================================================================
-- restReach: initial schema
--
-- Tables, integrity constraints, Row Level Security (RLS) policies and the
-- helper functions those policies use. The design is explained in
-- docs/ARCHITECTURE.md (sections 3, 4 and 7); keep the two in sync.
--
-- Security model:
--   * Every table has RLS enabled. With RLS on, nothing is readable or writable
--     unless a policy below allows it.
--   * Anonymous visitors can read the content of published businesses only.
--   * Signed-in users can also read and write businesses they are members of.
--   * Platform admins (the founders) can read and write everything.
--   * Helper functions live in the `private` schema, which is not exposed
--     through the Supabase Data API.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

-- Platform-wide ADMIN role (the founders). Rows are added by hand with SQL.
-- No policy allows creating them through the API.
create table public.platform_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- One row per restaurant: the tenant.
create table public.businesses (
  id             uuid primary key default gen_random_uuid(),
  slug           text not null unique
                   check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 63),
  name           text not null check (char_length(btrim(name)) between 1 and 120),
  description    text check (char_length(description) <= 2000),
  phone          text check (char_length(phone) <= 40),
  address_line_1 text check (char_length(address_line_1) <= 200),
  address_line_2 text check (char_length(address_line_2) <= 200),
  city           text check (char_length(city) <= 100),
  state          text check (char_length(state) <= 50),
  zip_code       text check (char_length(zip_code) <= 20),
  template       text not null default 'classic' check (template in ('classic')),
  is_published   boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Which users can manage which business.
create table public.memberships (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  business_id uuid not null references public.businesses (id) on delete cascade,
  role        text not null default 'owner' check (role in ('owner')),
  created_at  timestamptz not null default now(),
  unique (user_id, business_id)
);
create index memberships_business_id_idx on public.memberships (business_id);

-- Weekly hours as open periods. A day with no rows is closed.
-- day_of_week: 0 = Sunday ... 6 = Saturday.
-- A closes_at earlier than opens_at means the period ends after midnight.
create table public.business_hours (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  opens_at    time not null,
  closes_at   time not null,
  check (closes_at <> opens_at),
  unique (business_id, day_of_week, opens_at)
);

create table public.menu_categories (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 80),
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (id, business_id)  -- target of the composite foreign key in menu_items
);
create index menu_categories_business_id_display_order_idx
  on public.menu_categories (business_id, display_order);

create table public.menu_items (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  category_id   uuid not null,
  name          text not null check (char_length(btrim(name)) between 1 and 120),
  description   text check (char_length(description) <= 1000),
  price_cents   integer check (price_cents >= 0),  -- null = no price shown
  is_available  boolean not null default true,
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- The item's category must belong to the item's business.
  foreign key (category_id, business_id)
    references public.menu_categories (id, business_id) on delete cascade
);
create index menu_items_business_id_idx on public.menu_items (business_id);
create index menu_items_category_id_display_order_idx
  on public.menu_items (category_id, display_order);

-- At most one URL per kind per business. Only http(s) URLs, so a
-- `javascript:` link can never reach a public page.
create table public.business_links (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  kind        text not null
                check (kind in ('instagram', 'facebook', 'ordering', 'reservations')),
  url         text not null check (url ~* '^https?://' and char_length(url) <= 2048),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (business_id, kind)
);

-- Image metadata. The files live in the 'business-images' Storage bucket,
-- under a folder named after the business ID.
create table public.business_images (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  storage_path  text not null unique check (char_length(storage_path) <= 300),
  alt_text      text check (char_length(alt_text) <= 300),
  placement     text not null default 'gallery' check (placement in ('hero', 'gallery')),
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  check (starts_with(storage_path, business_id::text || '/'))
);
create index business_images_business_id_display_order_idx
  on public.business_images (business_id, display_order);

comment on table public.platform_admins is
  'Users with the platform-wide ADMIN role (the founders). Managed with SQL only.';
comment on table public.businesses is
  'One row per restaurant (the tenant). Readable by anyone once is_published is true.';
comment on table public.memberships is
  'Which users can manage which business, and in what role.';
comment on table public.business_hours is
  'Weekly opening hours as open periods. A day with no rows is closed. day_of_week 0 = Sunday.';
comment on table public.menu_categories is
  'Menu sections, ordered by display_order.';
comment on table public.menu_items is
  'Dishes, ordered by display_order within a category. Prices in cents; null price = none shown.';
comment on table public.business_links is
  'Instagram, Facebook, online ordering and reservation links. At most one per kind.';
comment on table public.business_images is
  'Metadata for images stored in the business-images Storage bucket.';


-- -----------------------------------------------------------------------------
-- Helper functions for RLS policies
--
-- `security definer` lets them read memberships and platform_admins without
-- triggering those tables' own policies (which would recurse). An empty
-- search_path prevents search-path hijacking.
-- -----------------------------------------------------------------------------

create schema private;

create function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admins
    where user_id = (select auth.uid())
  );
$$;

create function private.can_manage_business(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_platform_admin()
    or exists (
      select 1
      from public.memberships
      where business_id = target_business_id
        and user_id = (select auth.uid())
    );
$$;

create function private.is_published_business(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.businesses
    where id = target_business_id
      and is_published
  );
$$;


-- -----------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger set_updated_at before update on public.businesses
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.menu_categories
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.menu_items
  for each row execute function private.set_updated_at();
create trigger set_updated_at before update on public.business_links
  for each row execute function private.set_updated_at();

-- RLS works on rows, not columns. This trigger stops owners from changing the
-- fields only admins may change: slug (it's the public URL), template and
-- published status. Trusted backend roles (migrations, the SQL editor and the
-- secret key) are not restricted.
create function private.protect_business_admin_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  if (new.slug, new.template, new.is_published)
       is distinct from (old.slug, old.template, old.is_published)
     and not private.is_platform_admin()
  then
    raise exception 'Only platform admins can change a business''s slug, template or published status'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  return new;
end;
$$;

create trigger protect_business_admin_fields before update on public.businesses
  for each row execute function private.protect_business_admin_fields();


-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------

alter table public.platform_admins enable row level security;
alter table public.businesses enable row level security;
alter table public.memberships enable row level security;
alter table public.business_hours enable row level security;
alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.business_links enable row level security;
alter table public.business_images enable row level security;

-- platform_admins: a user can only see their own row; that's how the app
-- checks admin status. No write policies: admins are managed with SQL only.
create policy "Users can read their own admin row"
  on public.platform_admins for select to authenticated
  using (user_id = (select auth.uid()));

-- businesses
create policy "Anonymous visitors can read published businesses"
  on public.businesses for select to anon
  using (is_published);

create policy "Users can read published businesses and businesses they manage"
  on public.businesses for select to authenticated
  using (is_published or private.can_manage_business(id));

create policy "Admins can create businesses"
  on public.businesses for insert to authenticated
  with check ((select private.is_platform_admin()));

create policy "Members and admins can update their businesses"
  on public.businesses for update to authenticated
  using (private.can_manage_business(id))
  with check (private.can_manage_business(id));

create policy "Admins can delete businesses"
  on public.businesses for delete to authenticated
  using ((select private.is_platform_admin()));

-- memberships: users see their own; only admins grant or remove access.
create policy "Users can read their own memberships; admins can read all"
  on public.memberships for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_platform_admin()));

create policy "Admins can create memberships"
  on public.memberships for insert to authenticated
  with check ((select private.is_platform_admin()));

create policy "Admins can update memberships"
  on public.memberships for update to authenticated
  using ((select private.is_platform_admin()))
  with check ((select private.is_platform_admin()));

create policy "Admins can delete memberships"
  on public.memberships for delete to authenticated
  using ((select private.is_platform_admin()));

-- Restaurant content tables. All five follow the same pattern:
--   anonymous visitors:  read rows of published businesses
--   signed-in users:     read rows of published businesses and businesses they manage
--   members and admins:  create, update and delete rows of businesses they manage
-- `with check` also stops a row from being moved into a business the user
-- doesn't manage.

-- business_hours
create policy "Anonymous visitors can read hours of published businesses"
  on public.business_hours for select to anon
  using (private.is_published_business(business_id));

create policy "Users can read hours of published businesses and businesses they manage"
  on public.business_hours for select to authenticated
  using (private.is_published_business(business_id) or private.can_manage_business(business_id));

create policy "Members and admins can create hours"
  on public.business_hours for insert to authenticated
  with check (private.can_manage_business(business_id));

create policy "Members and admins can update hours"
  on public.business_hours for update to authenticated
  using (private.can_manage_business(business_id))
  with check (private.can_manage_business(business_id));

create policy "Members and admins can delete hours"
  on public.business_hours for delete to authenticated
  using (private.can_manage_business(business_id));

-- menu_categories
create policy "Anonymous visitors can read menu categories of published businesses"
  on public.menu_categories for select to anon
  using (private.is_published_business(business_id));

create policy "Users can read menu categories of published businesses and businesses they manage"
  on public.menu_categories for select to authenticated
  using (private.is_published_business(business_id) or private.can_manage_business(business_id));

create policy "Members and admins can create menu categories"
  on public.menu_categories for insert to authenticated
  with check (private.can_manage_business(business_id));

create policy "Members and admins can update menu categories"
  on public.menu_categories for update to authenticated
  using (private.can_manage_business(business_id))
  with check (private.can_manage_business(business_id));

create policy "Members and admins can delete menu categories"
  on public.menu_categories for delete to authenticated
  using (private.can_manage_business(business_id));

-- menu_items
create policy "Anonymous visitors can read menu items of published businesses"
  on public.menu_items for select to anon
  using (private.is_published_business(business_id));

create policy "Users can read menu items of published businesses and businesses they manage"
  on public.menu_items for select to authenticated
  using (private.is_published_business(business_id) or private.can_manage_business(business_id));

create policy "Members and admins can create menu items"
  on public.menu_items for insert to authenticated
  with check (private.can_manage_business(business_id));

create policy "Members and admins can update menu items"
  on public.menu_items for update to authenticated
  using (private.can_manage_business(business_id))
  with check (private.can_manage_business(business_id));

create policy "Members and admins can delete menu items"
  on public.menu_items for delete to authenticated
  using (private.can_manage_business(business_id));

-- business_links
create policy "Anonymous visitors can read links of published businesses"
  on public.business_links for select to anon
  using (private.is_published_business(business_id));

create policy "Users can read links of published businesses and businesses they manage"
  on public.business_links for select to authenticated
  using (private.is_published_business(business_id) or private.can_manage_business(business_id));

create policy "Members and admins can create links"
  on public.business_links for insert to authenticated
  with check (private.can_manage_business(business_id));

create policy "Members and admins can update links"
  on public.business_links for update to authenticated
  using (private.can_manage_business(business_id))
  with check (private.can_manage_business(business_id));

create policy "Members and admins can delete links"
  on public.business_links for delete to authenticated
  using (private.can_manage_business(business_id));

-- business_images
create policy "Anonymous visitors can read images of published businesses"
  on public.business_images for select to anon
  using (private.is_published_business(business_id));

create policy "Users can read images of published businesses and businesses they manage"
  on public.business_images for select to authenticated
  using (private.is_published_business(business_id) or private.can_manage_business(business_id));

create policy "Members and admins can create images"
  on public.business_images for insert to authenticated
  with check (private.can_manage_business(business_id));

create policy "Members and admins can update images"
  on public.business_images for update to authenticated
  using (private.can_manage_business(business_id))
  with check (private.can_manage_business(business_id));

create policy "Members and admins can delete images"
  on public.business_images for delete to authenticated
  using (private.can_manage_business(business_id));


-- -----------------------------------------------------------------------------
-- Functions the app calls for multi-row edits that must be atomic
--
-- They run with the caller's permissions (security invoker), so RLS still
-- applies to every row they touch. Each one also checks access up front, so
-- an unauthorized call fails loudly instead of silently changing nothing.
-- -----------------------------------------------------------------------------

-- Replace a business's whole weekly schedule in one step.
-- periods: [{"day_of_week": 1, "opens_at": "11:00", "closes_at": "14:30"}, ...]
create function public.replace_business_hours(target_business_id uuid, periods jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not private.can_manage_business(target_business_id) then
    raise exception 'You do not have access to this business' using errcode = '42501';
  end if;

  if jsonb_typeof(periods) is distinct from 'array' then
    raise exception 'periods must be a JSON array' using errcode = '22023';
  end if;

  delete from public.business_hours
  where business_id = target_business_id;

  insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
  select target_business_id,
         (period ->> 'day_of_week')::smallint,
         (period ->> 'opens_at')::time,
         (period ->> 'closes_at')::time
  from jsonb_array_elements(periods) as period;
end;
$$;

-- Set display_order from the position of each ID in the array. IDs that
-- don't belong to the target business (or category) are ignored.
create function public.reorder_menu_categories(
  target_business_id uuid,
  ordered_category_ids uuid[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not private.can_manage_business(target_business_id) then
    raise exception 'You do not have access to this business' using errcode = '42501';
  end if;

  update public.menu_categories as category
  set display_order = ordering.new_display_order
  from unnest(ordered_category_ids) with ordinality as ordering (category_id, new_display_order)
  where category.id = ordering.category_id
    and category.business_id = target_business_id;
end;
$$;

create function public.reorder_menu_items(
  target_business_id uuid,
  target_category_id uuid,
  ordered_item_ids uuid[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not private.can_manage_business(target_business_id) then
    raise exception 'You do not have access to this business' using errcode = '42501';
  end if;

  update public.menu_items as item
  set display_order = ordering.new_display_order
  from unnest(ordered_item_ids) with ordinality as ordering (item_id, new_display_order)
  where item.id = ordering.item_id
    and item.business_id = target_business_id
    and item.category_id = target_category_id;
end;
$$;

create function public.reorder_business_images(
  target_business_id uuid,
  ordered_image_ids uuid[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not private.can_manage_business(target_business_id) then
    raise exception 'You do not have access to this business' using errcode = '42501';
  end if;

  update public.business_images as image
  set display_order = ordering.new_display_order
  from unnest(ordered_image_ids) with ordinality as ordering (image_id, new_display_order)
  where image.id = ordering.image_id
    and image.business_id = target_business_id;
end;
$$;


-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------

-- Policies run the helper functions as the querying role, so those roles need
-- access to them. The `private` schema itself is still not exposed by the API.
grant usage on schema private to anon, authenticated;
revoke all on all functions in schema private from public;
grant execute on function private.is_platform_admin() to authenticated;
grant execute on function private.can_manage_business(uuid) to authenticated;
grant execute on function private.is_published_business(uuid) to anon, authenticated;

-- Only signed-in users can call the edit functions (and RLS still applies).
revoke all on function public.replace_business_hours(uuid, jsonb) from public, anon;
revoke all on function public.reorder_menu_categories(uuid, uuid[]) from public, anon;
revoke all on function public.reorder_menu_items(uuid, uuid, uuid[]) from public, anon;
revoke all on function public.reorder_business_images(uuid, uuid[]) from public, anon;
grant execute on function public.replace_business_hours(uuid, jsonb) to authenticated;
grant execute on function public.reorder_menu_categories(uuid, uuid[]) to authenticated;
grant execute on function public.reorder_menu_items(uuid, uuid, uuid[]) to authenticated;
grant execute on function public.reorder_business_images(uuid, uuid[]) to authenticated;
