-- =============================================================================
-- Business rules: admin-only fields, the atomic edit functions, and the data
-- constraints that keep each tenant's rows consistent. Run with: npm run db:test
--
-- Everything runs in one transaction that is rolled back at the end.
--
-- Fixtures
--   users       owner A   11111111-1111-4111-8111-111111111111
--               owner B   22222222-2222-4222-8222-222222222222
--               admin     33333333-3333-4333-8333-333333333333
--   businesses  A         aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa  published, owner A
--               B         bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb  published, owner B
-- =============================================================================

begin;
create extension if not exists pgtap with schema extensions;
select plan(27);


-- -----------------------------------------------------------------------------
-- Helpers (same as in tenant_isolation.test.sql; rolled back with everything else)
-- -----------------------------------------------------------------------------
create schema tests;
grant usage on schema tests to anon, authenticated;

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

create function tests.sign_out()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;


-- -----------------------------------------------------------------------------
-- Fixtures
-- -----------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'owner-a@test.local'),
  ('22222222-2222-4222-8222-222222222222', 'owner-b@test.local'),
  ('33333333-3333-4333-8333-333333333333', 'admin@test.local');

insert into public.platform_admins (user_id)
values ('33333333-3333-4333-8333-333333333333');

insert into public.businesses (id, slug, name, is_published, updated_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'rules-business-a', 'Business A', true, '2000-01-01'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'rules-business-b', 'Business B', true, '2000-01-01');

insert into public.memberships (user_id, business_id) values
  ('11111111-1111-4111-8111-111111111111', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  ('22222222-2222-4222-8222-222222222222', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');

insert into public.business_hours (business_id, day_of_week, opens_at, closes_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 5, '08:00', '12:00'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 3, '10:00', '20:00');

insert into public.menu_categories (id, business_id, name, display_order) values
  ('ca000001-0000-4000-8000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'First', 1),
  ('ca000002-0000-4000-8000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Second', 2),
  ('cb000001-0000-4000-8000-000000000000', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Other', 1);

insert into public.menu_items (id, business_id, category_id, name, display_order) values
  ('da000001-0000-4000-8000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'ca000001-0000-4000-8000-000000000000', 'Item one', 1),
  ('da000002-0000-4000-8000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'ca000001-0000-4000-8000-000000000000', 'Item two', 2),
  ('db000001-0000-4000-8000-000000000000', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'cb000001-0000-4000-8000-000000000000', 'Other item', 0);

insert into public.business_images (id, business_id, storage_path) values
  ('fb000001-0000-4000-8000-000000000000', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/photo.webp');


-- -----------------------------------------------------------------------------
-- Admin-only fields
-- -----------------------------------------------------------------------------
select tests.sign_in_as('11111111-1111-4111-8111-111111111111');

select throws_ok(
  $$ update public.businesses set slug = 'new-slug' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', 'Only platform admins can change a business''s slug, template or published status',
  'owners cannot change their slug (it is their public URL)'
);

select throws_ok(
  $$ update public.businesses set is_published = false where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', 'Only platform admins can change a business''s slug, template or published status',
  'owners cannot publish or unpublish their site'
);

select throws_ok(
  $$ update public.businesses set template = 'modern' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  '42501', 'Only platform admins can change a business''s slug, template or published status',
  'owners cannot change their template'
);

select lives_ok(
  $$ update public.businesses set name = 'Business A renamed', description = 'New description'
     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'owners can still edit the rest of their business information'
);

select tests.sign_in_as('33333333-3333-4333-8333-333333333333');

select lives_ok(
  $$ update public.businesses set slug = 'rules-business-a-renamed', is_published = false
     where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' $$,
  'admins can change the slug and published status'
);

reset role;

select is(
  (select updated_at from public.businesses where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  now(),
  'updated_at is set automatically on every update'
);


-- -----------------------------------------------------------------------------
-- Atomic edit functions
-- -----------------------------------------------------------------------------
select tests.sign_in_as('11111111-1111-4111-8111-111111111111');

select lives_ok(
  $$ select public.replace_business_hours('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[
       {"day_of_week": 2, "opens_at": "11:00", "closes_at": "14:30"},
       {"day_of_week": 2, "opens_at": "17:00", "closes_at": "22:00"}
     ]'::jsonb) $$,
  'owners can replace their weekly hours'
);

select results_eq(
  $$ select day_of_week, opens_at, closes_at from public.business_hours
     where business_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' order by opens_at $$,
  $$ values (2::smallint, '11:00'::time, '14:30'::time), (2::smallint, '17:00'::time, '22:00'::time) $$,
  'the new weekly schedule fully replaces the old one, including split shifts'
);

select throws_ok(
  $$ select public.replace_business_hours('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '[]'::jsonb) $$,
  '42501', null,
  'owners cannot replace another business''s hours'
);

select throws_ok(
  $$ select public.replace_business_hours('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '{}'::jsonb) $$,
  '22023', null,
  'replace_business_hours rejects anything but a JSON array'
);

select lives_ok(
  $$ select public.reorder_menu_categories('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', array[
       'ca000002-0000-4000-8000-000000000000', 'ca000001-0000-4000-8000-000000000000'
     ]::uuid[]) $$,
  'owners can reorder their menu categories'
);

select results_eq(
  $$ select name from public.menu_categories
     where business_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' order by display_order $$,
  $$ values ('Second'), ('First') $$,
  'categories are saved in the new order'
);

select throws_ok(
  $$ select public.reorder_menu_categories('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       array['cb000001-0000-4000-8000-000000000000']::uuid[]) $$,
  '42501', null,
  'owners cannot reorder another business''s menu'
);

select lives_ok(
  $$ select public.reorder_menu_items('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
       'ca000001-0000-4000-8000-000000000000', array[
         'db000001-0000-4000-8000-000000000000',
         'da000002-0000-4000-8000-000000000000',
         'da000001-0000-4000-8000-000000000000'
       ]::uuid[]) $$,
  'reordering items with another business''s item ID mixed in still succeeds'
);

select results_eq(
  $$ select name from public.menu_items
     where category_id = 'ca000001-0000-4000-8000-000000000000' order by display_order $$,
  $$ values ('Item two'), ('Item one') $$,
  'items are saved in the new order'
);

select throws_ok(
  $$ select public.reorder_business_images('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
       array['fb000001-0000-4000-8000-000000000000']::uuid[]) $$,
  '42501', null,
  'owners cannot reorder another business''s photos'
);

reset role;

select results_eq(
  $$ select day_of_week, opens_at from public.business_hours
     where business_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' $$,
  $$ values (3::smallint, '10:00'::time) $$,
  'the other business''s hours are untouched'
);

select results_eq(
  $$ select display_order from public.menu_items where id = 'db000001-0000-4000-8000-000000000000' $$,
  $$ values (0) $$,
  'the other business''s menu item was not reordered'
);

select tests.sign_out();

select throws_ok(
  $$ select public.replace_business_hours('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '[]'::jsonb) $$,
  '42501', null,
  'anonymous visitors cannot call the edit functions'
);


-- -----------------------------------------------------------------------------
-- Data constraints (checked as the database owner, so RLS is not involved)
-- -----------------------------------------------------------------------------
reset role;

select throws_ok(
  $$ insert into public.businesses (slug, name) values ('Joes Pizza', 'Joe''s Pizza') $$,
  '23514', null,
  'slugs must be lowercase letters, numbers and single hyphens'
);

select throws_ok(
  $$ insert into public.business_links (business_id, kind, url)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ordering', 'javascript:alert(1)') $$,
  '23514', null,
  'links must be http or https URLs'
);

select throws_ok(
  $$ insert into public.business_images (business_id, storage_path)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/photo2.webp') $$,
  '23514', null,
  'an image must be stored in its own business''s folder'
);

select throws_ok(
  $$ insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 4, '10:00', '10:00') $$,
  '23514', null,
  'an open period cannot start and end at the same time'
);

select throws_ok(
  $$ insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 7, '10:00', '12:00') $$,
  '23514', null,
  'day_of_week must be between 0 (Sunday) and 6 (Saturday)'
);

select throws_ok(
  $$ insert into public.menu_items (business_id, category_id, name)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'cb000001-0000-4000-8000-000000000000', 'Wrong') $$,
  '23503', null,
  'a menu item cannot use another business''s category'
);

select throws_ok(
  $$ insert into public.menu_items (business_id, category_id, name, price_cents)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'ca000001-0000-4000-8000-000000000000', 'Refund', -100) $$,
  '23514', null,
  'prices cannot be negative'
);

select lives_ok(
  $$ insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
     values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 5, '18:00', '02:00') $$,
  'an open period can run past midnight'
);

select * from finish();
rollback;
