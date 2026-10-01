-- =============================================================================
-- Tenant isolation: what each kind of user can read and write, table by table.
-- The most important tests in the project. Run with: npm run db:test
--
-- Everything runs in one transaction that is rolled back at the end, so the
-- fixtures and helpers never touch your local data.
--
-- Fixtures
--   users       owner A   11111111-1111-4111-8111-111111111111
--               owner B   22222222-2222-4222-8222-222222222222
--               admin     33333333-3333-4333-8333-333333333333
--               outsider  44444444-4444-4444-8444-444444444444  signed in, no access
--   businesses  A         aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa  published,   owner A
--               B         bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb  unpublished, owner B
--               C         cccccccc-cccc-4ccc-8ccc-cccccccccccc  published,   owner B
--   Each business starts with one row in each of the five content tables.
-- =============================================================================

begin;
create extension if not exists pgtap with schema extensions;
select plan(47);


-- -----------------------------------------------------------------------------
-- Helpers (rolled back with everything else)
-- -----------------------------------------------------------------------------
create schema tests;
grant usage on schema tests to anon, authenticated;

-- Act as a signed-in user, the way the Supabase API does for each request.
create function tests.sign_in_as(user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text, true);
end;
$$;

-- Act as an anonymous visitor.
create function tests.sign_out()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end;
$$;

-- Fixture content rows visible to the current user, as (table, business letter).
-- security_invoker makes the view obey the RLS of whoever queries it.
create view tests.visible_content with (security_invoker = true) as
select
  content.table_name,
  case content.business_id
    when 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' then 'A'
    when 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' then 'B'
    when 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' then 'C'
  end as business
from (
  select 'business_hours' as table_name, business_id from public.business_hours
  union all select 'menu_categories', business_id from public.menu_categories
  union all select 'menu_items', business_id from public.menu_items
  union all select 'business_links', business_id from public.business_links
  union all select 'business_images', business_id from public.business_images
) as content
where content.business_id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
);
grant select on tests.visible_content to anon, authenticated;

-- Try a harmless update on every content row of a business.
-- Returns how many rows each table let the current user change.
create function tests.update_content(target_business_id uuid)
returns table (table_name text, rows_changed integer)
language plpgsql
as $$
begin
  table_name := 'business_hours';
  update public.business_hours set business_id = business_id where business_id = target_business_id;
  get diagnostics rows_changed = row_count;
  return next;

  table_name := 'menu_categories';
  update public.menu_categories set business_id = business_id where business_id = target_business_id;
  get diagnostics rows_changed = row_count;
  return next;

  table_name := 'menu_items';
  update public.menu_items set business_id = business_id where business_id = target_business_id;
  get diagnostics rows_changed = row_count;
  return next;

  table_name := 'business_links';
  update public.business_links set business_id = business_id where business_id = target_business_id;
  get diagnostics rows_changed = row_count;
  return next;

  table_name := 'business_images';
  update public.business_images set business_id = business_id where business_id = target_business_id;
  get diagnostics rows_changed = row_count;
  return next;
end;
$$;

-- Try to delete every content row of a business.
-- Returns how many rows each table let the current user delete.
create function tests.delete_content(target_business_id uuid)
returns table (table_name text, rows_deleted integer)
language plpgsql
as $$
begin
  table_name := 'business_hours';
  delete from public.business_hours where business_id = target_business_id;
  get diagnostics rows_deleted = row_count;
  return next;

  -- Items before categories, because deleting a category deletes its items.
  table_name := 'menu_items';
  delete from public.menu_items where business_id = target_business_id;
  get diagnostics rows_deleted = row_count;
  return next;

  table_name := 'menu_categories';
  delete from public.menu_categories where business_id = target_business_id;
  get diagnostics rows_deleted = row_count;
  return next;

  table_name := 'business_links';
  delete from public.business_links where business_id = target_business_id;
  get diagnostics rows_deleted = row_count;
  return next;

  table_name := 'business_images';
  delete from public.business_images where business_id = target_business_id;
  get diagnostics rows_deleted = row_count;
  return next;
end;
$$;

-- Try to add one row to every content table of a business.
-- Returns 'allowed', or the error code if the insert was rejected.
create function tests.add_content(target_business_id uuid, target_category_id uuid)
returns table (table_name text, outcome text)
language plpgsql
as $$
begin
  table_name := 'business_hours';
  begin
    insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
    values (target_business_id, 2, '09:00', '17:00');
    outcome := 'allowed';
  exception when others then
    outcome := sqlstate;
  end;
  return next;

  table_name := 'menu_categories';
  begin
    insert into public.menu_categories (business_id, name)
    values (target_business_id, 'Added category');
    outcome := 'allowed';
  exception when others then
    outcome := sqlstate;
  end;
  return next;

  table_name := 'menu_items';
  begin
    insert into public.menu_items (business_id, category_id, name, price_cents)
    values (target_business_id, target_category_id, 'Added item', 500);
    outcome := 'allowed';
  exception when others then
    outcome := sqlstate;
  end;
  return next;

  table_name := 'business_links';
  begin
    insert into public.business_links (business_id, kind, url)
    values (target_business_id, 'facebook', 'https://facebook.test/added');
    outcome := 'allowed';
  exception when others then
    outcome := sqlstate;
  end;
  return next;

  table_name := 'business_images';
  begin
    insert into public.business_images (business_id, storage_path)
    values (target_business_id, target_business_id || '/added.webp');
    outcome := 'allowed';
  exception when others then
    outcome := sqlstate;
  end;
  return next;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;


-- -----------------------------------------------------------------------------
-- Fixtures (created as the database owner, which bypasses RLS)
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'owner-a@test.local'),
  ('22222222-2222-4222-8222-222222222222', 'owner-b@test.local'),
  ('33333333-3333-4333-8333-333333333333', 'admin@test.local'),
  ('44444444-4444-4444-8444-444444444444', 'outsider@test.local');

insert into public.platform_admins (user_id)
values ('33333333-3333-4333-8333-333333333333');

insert into public.businesses (id, slug, name, is_published) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'test-business-a', 'Business A', true),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'test-business-b', 'Business B', false),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'test-business-c', 'Business C', true);

insert into public.memberships (user_id, business_id) values
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  ('22222222-2222-4222-8222-222222222222', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');

insert into public.menu_categories (id, business_id, name) values
  ('ca000000-0000-4000-8000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Category A'),
  ('cb000000-0000-4000-8000-000000000000', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Category B'),
  ('cc000000-0000-4000-8000-000000000000', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Category C');

insert into public.menu_items (business_id, category_id, name, price_cents)
select business_id, id, 'Item', 1000
from public.menu_categories
where business_id in (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
);

insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
select id, 1, '09:00', '17:00'
from public.businesses where slug like 'test-business-_';

insert into public.business_links (business_id, kind, url)
select id, 'instagram', 'https://instagram.test/' || slug
from public.businesses where slug like 'test-business-_';

insert into public.business_images (business_id, storage_path)
select id, id || '/photo.webp'
from public.businesses where slug like 'test-business-_';


-- -----------------------------------------------------------------------------
-- Anonymous visitors
-- -----------------------------------------------------------------------------
select tests.sign_out();

select results_eq(
  $$ select slug from public.businesses where slug like 'test-business-_' order by slug $$,
  $$ values ('test-business-a'), ('test-business-c') $$,
  'anonymous: sees published businesses only'
);

select results_eq(
  $$ select business, count(distinct table_name)::int from tests.visible_content
     group by business order by business $$,
  $$ values ('A', 5), ('C', 5) $$,
  'anonymous: sees content of published businesses only, in all five content tables'
);

select is_empty(
  $$ select 1 from public.memberships $$,
  'anonymous: sees no memberships'
);

select is_empty(
  $$ select 1 from public.platform_admins $$,
  'anonymous: sees no platform admins'
);

select results_eq(
  $$ select * from tests.add_content('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ca000000-0000-4000-8000-000000000000') $$,
  $$ values ('business_hours', '42501'), ('menu_categories', '42501'), ('menu_items', '42501'),
            ('business_links', '42501'), ('business_images', '42501') $$,
  'anonymous: cannot add content to any table'
);

select results_eq(
  $$ select * from tests.update_content('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  $$ values ('business_hours', 0), ('menu_categories', 0), ('menu_items', 0),
            ('business_links', 0), ('business_images', 0) $$,
  'anonymous: cannot change content in any table'
);

select results_eq(
  $$ select * from tests.delete_content('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  $$ values ('business_hours', 0), ('menu_items', 0), ('menu_categories', 0),
            ('business_links', 0), ('business_images', 0) $$,
  'anonymous: cannot delete content from any table'
);

select throws_ok(
  $$ insert into public.businesses (slug, name) values ('anon-business', 'Anon') $$,
  '42501', null,
  'anonymous: cannot create a business'
);

select is_empty(
  $$ update public.businesses set name = 'Changed' where slug = 'test-business-a' returning id $$,
  'anonymous: cannot change a business'
);


-- -----------------------------------------------------------------------------
-- Signed-in user with no memberships
-- -----------------------------------------------------------------------------
select tests.sign_in_as('44444444-4444-4444-8444-444444444444');

select results_eq(
  $$ select slug from public.businesses where slug like 'test-business-_' order by slug $$,
  $$ values ('test-business-a'), ('test-business-c') $$,
  'outsider: sees published businesses only'
);

select results_eq(
  $$ select business, count(distinct table_name)::int from tests.visible_content
     group by business order by business $$,
  $$ values ('A', 5), ('C', 5) $$,
  'outsider: sees content of published businesses only'
);

select is_empty(
  $$ update public.businesses set name = 'Changed' where slug like 'test-business-_' returning id $$,
  'outsider: cannot change any business'
);

select results_eq(
  $$ select * from tests.add_content('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ca000000-0000-4000-8000-000000000000') $$,
  $$ values ('business_hours', '42501'), ('menu_categories', '42501'), ('menu_items', '42501'),
            ('business_links', '42501'), ('business_images', '42501') $$,
  'outsider: cannot add content to a business they do not manage'
);


-- -----------------------------------------------------------------------------
-- Owner A (member of business A only)
-- -----------------------------------------------------------------------------
select tests.sign_in_as('11111111-1111-4111-8111-111111111111');

select results_eq(
  $$ select slug from public.businesses where slug like 'test-business-_' order by slug $$,
  $$ values ('test-business-a'), ('test-business-c') $$,
  'owner A: sees their business and published ones, not unpublished business B'
);

select results_eq(
  $$ select business, count(distinct table_name)::int from tests.visible_content
     group by business order by business $$,
  $$ values ('A', 5), ('C', 5) $$,
  'owner A: sees content of A and published C, not unpublished B'
);

select results_eq(
  $$ select business_id from public.memberships $$,
  $$ values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid) $$,
  'owner A: sees only their own membership'
);

select is_empty(
  $$ select 1 from public.platform_admins $$,
  'owner A: is not a platform admin'
);

select isnt_empty(
  $$ update public.businesses set phone = '(555) 010-0100' where slug = 'test-business-a' returning id $$,
  'owner A: can edit their own business'
);

select is_empty(
  $$ update public.businesses set phone = '(555) 010-0199'
     where slug in ('test-business-b', 'test-business-c') returning id $$,
  'owner A: cannot edit businesses they do not manage, published or not'
);

select is_empty(
  $$ delete from public.businesses where slug = 'test-business-a' returning id $$,
  'owner A: cannot delete their own business'
);

select throws_ok(
  $$ insert into public.businesses (slug, name) values ('owner-business', 'Owner') $$,
  '42501', null,
  'owner A: cannot create a business'
);

select results_eq(
  $$ select * from tests.update_content('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') $$,
  $$ values ('business_hours', 1), ('menu_categories', 1), ('menu_items', 1),
            ('business_links', 1), ('business_images', 1) $$,
  'owner A: can change their own content in every table'
);

select results_eq(
  $$ select * from tests.update_content('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  $$ values ('business_hours', 0), ('menu_categories', 0), ('menu_items', 0),
            ('business_links', 0), ('business_images', 0) $$,
  'owner A: cannot change content of unpublished business B'
);

select results_eq(
  $$ select * from tests.update_content('cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  $$ values ('business_hours', 0), ('menu_categories', 0), ('menu_items', 0),
            ('business_links', 0), ('business_images', 0) $$,
  'owner A: cannot change content of published business C'
);

select results_eq(
  $$ select * from tests.delete_content('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  $$ values ('business_hours', 0), ('menu_items', 0), ('menu_categories', 0),
            ('business_links', 0), ('business_images', 0) $$,
  'owner A: cannot delete content of business B'
);

select results_eq(
  $$ select * from tests.delete_content('cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  $$ values ('business_hours', 0), ('menu_items', 0), ('menu_categories', 0),
            ('business_links', 0), ('business_images', 0) $$,
  'owner A: cannot delete content of business C'
);

select results_eq(
  $$ select * from tests.add_content('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ca000000-0000-4000-8000-000000000000') $$,
  $$ values ('business_hours', 'allowed'), ('menu_categories', 'allowed'), ('menu_items', 'allowed'),
            ('business_links', 'allowed'), ('business_images', 'allowed') $$,
  'owner A: can add content to their own business in every table'
);

select results_eq(
  $$ select * from tests.add_content('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cb000000-0000-4000-8000-000000000000') $$,
  $$ values ('business_hours', '42501'), ('menu_categories', '42501'), ('menu_items', '42501'),
            ('business_links', '42501'), ('business_images', '42501') $$,
  'owner A: cannot add content to business B'
);

select results_eq(
  $$ select * from tests.add_content('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'cc000000-0000-4000-8000-000000000000') $$,
  $$ values ('business_hours', '42501'), ('menu_categories', '42501'), ('menu_items', '42501'),
            ('business_links', '42501'), ('business_images', '42501') $$,
  'owner A: cannot add content to business C'
);

select throws_ok(
  $$ update public.business_links set business_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
     where business_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', null,
  'owner A: cannot move their content into another business'
);

select throws_ok(
  $$ insert into public.menu_items (business_id, category_id, name)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cc000000-0000-4000-8000-000000000000', 'Sneaky') $$,
  '23503', null,
  'owner A: cannot put their item in another business''s category'
);

select throws_ok(
  $$ insert into public.memberships (user_id, business_id)
     values ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  '42501', null,
  'owner A: cannot give themselves access to another business'
);

select throws_ok(
  $$ insert into public.platform_admins (user_id) values ('11111111-1111-4111-8111-111111111111') $$,
  '42501', null,
  'owner A: cannot make themselves a platform admin'
);


-- -----------------------------------------------------------------------------
-- Owner B (member of unpublished B and published C)
-- -----------------------------------------------------------------------------
select tests.sign_in_as('22222222-2222-4222-8222-222222222222');

select results_eq(
  $$ select slug from public.businesses where slug like 'test-business-_' order by slug $$,
  $$ values ('test-business-a'), ('test-business-b'), ('test-business-c') $$,
  'owner B: sees their unpublished business B, plus published ones'
);

select results_eq(
  $$ select business, count(distinct table_name)::int from tests.visible_content
     group by business order by business $$,
  $$ values ('A', 5), ('B', 5), ('C', 5) $$,
  'owner B: sees content of their unpublished business B'
);


-- -----------------------------------------------------------------------------
-- Platform admin
-- -----------------------------------------------------------------------------
select tests.sign_in_as('33333333-3333-4333-8333-333333333333');

select results_eq(
  $$ select slug from public.businesses where slug like 'test-business-_' order by slug $$,
  $$ values ('test-business-a'), ('test-business-b'), ('test-business-c') $$,
  'admin: sees every business, published or not'
);

select results_eq(
  $$ select business, count(distinct table_name)::int from tests.visible_content
     group by business order by business $$,
  $$ values ('A', 5), ('B', 5), ('C', 5) $$,
  'admin: sees content of every business'
);

select results_eq(
  $$ select count(*)::int from public.memberships
     where business_id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                           'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                           'cccccccc-cccc-4ccc-8ccc-cccccccccccc') $$,
  $$ values (3) $$,
  'admin: sees every membership'
);

select isnt_empty(
  $$ update public.businesses set is_published = true where slug = 'test-business-b' returning id $$,
  'admin: can edit any business, including publishing it'
);

select results_eq(
  $$ select * from tests.update_content('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  $$ values ('business_hours', 1), ('menu_categories', 1), ('menu_items', 1),
            ('business_links', 1), ('business_images', 1) $$,
  'admin: can change content of any business'
);

select results_eq(
  $$ select * from tests.add_content('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'cb000000-0000-4000-8000-000000000000') $$,
  $$ values ('business_hours', 'allowed'), ('menu_categories', 'allowed'), ('menu_items', 'allowed'),
            ('business_links', 'allowed'), ('business_images', 'allowed') $$,
  'admin: can add content to any business'
);

select lives_ok(
  $$ insert into public.businesses (slug, name) values ('test-business-d', 'Business D') $$,
  'admin: can create a business'
);

select lives_ok(
  $$ insert into public.memberships (user_id, business_id)
     values ('11111111-1111-4111-8111-111111111111', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  'admin: can give an owner access to a business'
);

-- Removing access takes effect on the very next request.
delete from public.memberships
where user_id = '11111111-1111-4111-8111-111111111111'
  and business_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select tests.sign_in_as('11111111-1111-4111-8111-111111111111');

select is_empty(
  $$ update public.businesses set phone = '(555) 010-0101' where slug = 'test-business-a' returning id $$,
  'owner A: loses access as soon as an admin removes their membership'
);

select tests.sign_in_as('33333333-3333-4333-8333-333333333333');

select isnt_empty(
  $$ delete from public.businesses where slug = 'test-business-c' returning id $$,
  'admin: can delete a business'
);


-- -----------------------------------------------------------------------------
-- Owners can delete their own content
-- -----------------------------------------------------------------------------
select tests.sign_in_as('22222222-2222-4222-8222-222222222222');

select results_eq(
  $$ select table_name, rows_deleted > 0 from tests.delete_content('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') $$,
  $$ values ('business_hours', true), ('menu_items', true), ('menu_categories', true),
            ('business_links', true), ('business_images', true) $$,
  'owner B: can delete their own content in every table'
);


-- -----------------------------------------------------------------------------
-- Guard for future migrations
-- -----------------------------------------------------------------------------
reset role;

select is_empty(
  $$ select c.relname
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity $$,
  'every table in the public schema has Row Level Security enabled'
);

select * from finish();
rollback;
