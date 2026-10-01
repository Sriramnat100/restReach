-- =============================================================================
-- Local development seed data
--
-- Loaded by `npm run db:reset` and on the first `npm run db:start`.
-- Never applied to hosted projects. Everything here is fictional.
--
-- Dev logins (local only, password for all three: restreach-dev):
--   admin@example.com        platform admin
--   owner-joes@example.com   owns Joe's Pizza
--   owner-thai@example.com   owns Thai Garden and Pasta House (unpublished draft)
-- =============================================================================

-- Users ------------------------------------------------------------------------
-- Inserted directly into Supabase Auth's tables, with an email identity each,
-- so they can sign in with email and password once login exists (Milestone 2).
with dev_users (id, email) as (
  values
    ('5eed0000-0000-4000-8000-0000000000ad'::uuid, 'admin@example.com'),
    ('5eed0000-0000-4000-8000-00000000000a'::uuid, 'owner-joes@example.com'),
    ('5eed0000-0000-4000-8000-00000000000b'::uuid, 'owner-thai@example.com')
),
inserted_users as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  )
  select
    '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email,
    extensions.crypt('restreach-dev', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{}', now(), now(),
    '', '', '', ''
  from dev_users
  returning id, email
)
insert into auth.identities (
  provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select
  id::text, id,
  jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true),
  'email', now(), now(), now()
from inserted_users;

insert into public.platform_admins (user_id)
values ('5eed0000-0000-4000-8000-0000000000ad');

-- Businesses -------------------------------------------------------------------
insert into public.businesses (
  id, slug, name, description, phone,
  address_line_1, city, state, zip_code, is_published
) values
  (
    '5eedb000-0000-4000-8000-00000000000a', 'joes-pizza', 'Joe''s Pizza',
    'Neighborhood pizzeria serving New York-style pies since 1998.',
    '(555) 010-0001', '123 Main Street', 'Springfield', 'IL', '62701', true
  ),
  (
    '5eedb000-0000-4000-8000-00000000000b', 'thai-garden', 'Thai Garden',
    'Family-run Thai kitchen. Lunch and dinner, closed Mondays.',
    '(555) 010-0002', '48 Oak Avenue', 'Springfield', 'IL', '62702', true
  ),
  (
    '5eedb000-0000-4000-8000-00000000000c', 'pasta-house', 'Pasta House',
    'Fresh pasta made in house every morning. Opening soon.',
    '(555) 010-0003', '9 Elm Street', 'Springfield', 'IL', '62703', false
  );

insert into public.memberships (user_id, business_id) values
  ('5eed0000-0000-4000-8000-00000000000a', '5eedb000-0000-4000-8000-00000000000a'),
  ('5eed0000-0000-4000-8000-00000000000b', '5eedb000-0000-4000-8000-00000000000b'),
  ('5eed0000-0000-4000-8000-00000000000b', '5eedb000-0000-4000-8000-00000000000c');

-- Hours ------------------------------------------------------------------------
-- Joe's Pizza: one period per day.
insert into public.business_hours (business_id, day_of_week, opens_at, closes_at) values
  ('5eedb000-0000-4000-8000-00000000000a', 0, '12:00', '21:00'),
  ('5eedb000-0000-4000-8000-00000000000a', 1, '11:00', '22:00'),
  ('5eedb000-0000-4000-8000-00000000000a', 2, '11:00', '22:00'),
  ('5eedb000-0000-4000-8000-00000000000a', 3, '11:00', '22:00'),
  ('5eedb000-0000-4000-8000-00000000000a', 4, '11:00', '22:00'),
  ('5eedb000-0000-4000-8000-00000000000a', 5, '11:00', '23:00'),
  ('5eedb000-0000-4000-8000-00000000000a', 6, '11:00', '23:00');

-- Thai Garden: lunch and dinner every day except Monday (day 1).
insert into public.business_hours (business_id, day_of_week, opens_at, closes_at)
select '5eedb000-0000-4000-8000-00000000000b', day_of_week, period.opens_at, period.closes_at
from generate_series(0, 6) as day_of_week
cross join (values ('11:00'::time, '14:30'::time), ('17:00'::time, '21:30'::time))
  as period (opens_at, closes_at)
where day_of_week <> 1;

-- Pasta House has no hours yet, so its site would hide the hours section.

-- Menus ------------------------------------------------------------------------
insert into public.menu_categories (business_id, name, display_order) values
  ('5eedb000-0000-4000-8000-00000000000a', 'Pizzas', 1),
  ('5eedb000-0000-4000-8000-00000000000a', 'Sides', 2),
  ('5eedb000-0000-4000-8000-00000000000a', 'Drinks', 3),
  ('5eedb000-0000-4000-8000-00000000000b', 'Starters', 1),
  ('5eedb000-0000-4000-8000-00000000000b', 'Curries', 2),
  ('5eedb000-0000-4000-8000-00000000000b', 'Noodles', 3),
  ('5eedb000-0000-4000-8000-00000000000c', 'Fresh Pasta', 1);

insert into public.menu_items (
  business_id, category_id, name, description, price_cents, is_available, display_order
)
select category.business_id, category.id, item.name, item.description,
       item.price_cents, item.is_available, item.display_order
from (
  values
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Pizzas', 'Margherita', 'Tomato, fresh mozzarella, basil', 1400, true, 1),
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Pizzas', 'Pepperoni', 'Tomato, mozzarella, cup-and-char pepperoni', 1600, true, 2),
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Pizzas', 'Garden Veggie', 'Peppers, onions, mushrooms, olives', 1550, true, 3),
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Pizzas', 'White Clam', 'Clams, garlic, pecorino. Weekends only', 1900, false, 4),
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Sides', 'Garlic Knots', 'Six knots with marinara', 600, true, 1),
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Sides', 'Caesar Salad', null, 850, true, 2),
    ('5eedb000-0000-4000-8000-00000000000a'::uuid, 'Drinks', 'Fountain Soda', null, 250, true, 1),
    ('5eedb000-0000-4000-8000-00000000000b'::uuid, 'Starters', 'Spring Rolls', 'Crispy vegetable rolls, sweet chili sauce', 700, true, 1),
    ('5eedb000-0000-4000-8000-00000000000b'::uuid, 'Starters', 'Chicken Satay', 'Grilled skewers, peanut sauce', 900, true, 2),
    ('5eedb000-0000-4000-8000-00000000000b'::uuid, 'Curries', 'Green Curry', 'Coconut milk, Thai basil, bamboo shoots', 1500, true, 1),
    ('5eedb000-0000-4000-8000-00000000000b'::uuid, 'Curries', 'Massaman Curry', 'Potato, peanuts, slow-cooked beef', 1600, true, 2),
    ('5eedb000-0000-4000-8000-00000000000b'::uuid, 'Noodles', 'Pad Thai', 'Rice noodles, tamarind, peanuts', 1400, true, 1),
    ('5eedb000-0000-4000-8000-00000000000b'::uuid, 'Noodles', 'Pad See Ew', 'Wide noodles, Chinese broccoli, egg', 1400, true, 2),
    ('5eedb000-0000-4000-8000-00000000000c'::uuid, 'Fresh Pasta', 'Cacio e Pepe', 'Pecorino, black pepper', 1700, true, 1),
    ('5eedb000-0000-4000-8000-00000000000c'::uuid, 'Fresh Pasta', 'Market Ravioli', 'Changes daily', null, true, 2)
) as item (business_id, category_name, name, description, price_cents, is_available, display_order)
join public.menu_categories as category
  on category.business_id = item.business_id
 and category.name = item.category_name;

-- Links ------------------------------------------------------------------------
insert into public.business_links (business_id, kind, url) values
  ('5eedb000-0000-4000-8000-00000000000a', 'instagram', 'https://www.instagram.com/joespizza.example'),
  ('5eedb000-0000-4000-8000-00000000000a', 'facebook', 'https://www.facebook.com/joespizza.example'),
  ('5eedb000-0000-4000-8000-00000000000a', 'ordering', 'https://order.example.com/joes-pizza'),
  ('5eedb000-0000-4000-8000-00000000000b', 'instagram', 'https://www.instagram.com/thaigarden.example'),
  ('5eedb000-0000-4000-8000-00000000000b', 'ordering', 'https://order.example.com/thai-garden'),
  ('5eedb000-0000-4000-8000-00000000000b', 'reservations', 'https://reserve.example.com/thai-garden');
