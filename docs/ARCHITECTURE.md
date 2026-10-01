# restReach Architecture

**Status:** proposal for review (Milestone 0) · **Last updated:** 2026-10-01

Only the scaffold and folder layout (§2) exist today. Everything else describes the design we'll build once it's approved. As each milestone lands, this document is updated to match the code.

Read [SPEC.md](./SPEC.md) first for what we're building and why. [ROADMAP.md](./ROADMAP.md) has the build order.

## Contents

1. [Overview](#1-overview)
2. [Code organization](#2-code-organization)
3. [Multi-tenancy](#3-multi-tenancy)
4. [Database design](#4-database-design)
5. [Authentication](#5-authentication)
6. [Authorization](#6-authorization)
7. [Row Level Security strategy](#7-row-level-security-strategy)
8. [Public website rendering](#8-public-website-rendering)
9. [Customer dashboard](#9-customer-dashboard)
10. [Admin dashboard](#10-admin-dashboard)
11. [File storage](#11-file-storage)
12. [Testing strategy](#12-testing-strategy)
13. [Future: custom domains](#13-future-custom-domains)
14. [Future: lead intelligence integration](#14-future-lead-intelligence-integration)
15. [Decisions pending review](#15-decisions-pending-review)

---

## 1. Overview

restReach is **one Next.js application** (App Router, TypeScript, Tailwind CSS) deployed on **Vercel**, backed by **one Supabase project** (Postgres, Auth, Storage). There are no other services.

One codebase serves three surfaces:

| Surface | Path | Used by | Data it can reach |
|---|---|---|---|
| Public restaurant sites | `/sites/[slug]` | Anyone | Published restaurant content, read-only |
| Customer dashboard | `/dashboard/…` | Owners (and admins) | Only businesses the user can access |
| Internal admin | `/admin/…` | Admins | All businesses |

```
Browser
   │
   ▼
Vercel: Next.js app
   ├─ proxy.ts ............ refreshes the Supabase session cookie; optimistic redirects only
   ├─ app/sites/[slug] .... public sites (Server Components, read-only)
   ├─ app/dashboard ....... owner dashboard (Server Components + Server Actions)
   ├─ app/admin ........... admin dashboard (Server Components + Server Actions)
   └─ lib/ ................ auth, permissions, tenant resolution, data access (server-only); validation
          │
          │  supabase-js, using the signed-in user's session, so Row Level Security applies
          ▼
Supabase
   ├─ Postgres ..... all restaurant data, Row Level Security on every table
   ├─ Auth ......... users, sessions, invite and password-reset emails
   └─ Storage ...... restaurant images (bucket: business-images)
```

Principles behind the rest of this document:

- **Server first.** Pages are Server Components that load data on the server. Client Components are used only for interactive pieces such as forms with live feedback, reordering, and image upload.
- **Mutations are Server Actions.** Each one validates input, checks permissions, writes through `lib/db`, then refreshes the affected public site.
- **Defense in depth.** Server-side permission checks and Postgres Row Level Security each prevent cross-tenant access independently.
- **No speculative abstractions.** One template, one database, plain functions. We add structure when a second real use case shows up.

## 2. Code organization

```
app/
  page.tsx                  placeholder home page
  login/                    sign-in page (M2)
  auth/confirm/             verifies links from auth emails: invites, password resets (M2)
  sites/[slug]/             public restaurant site (M3)
  dashboard/                owner dashboard; page.tsx lists the user's businesses (M2)
    [businessId]/           everything below is scoped to one business
      business/ hours/ menu/ photos/ links/
  admin/                    internal admin (M7)
    businesses/             list, create, view, edit businesses
    customers/              restaurant owner accounts
components/
  admin/  dashboard/        UI used only in that area
  restaurant/               display pieces for restaurant data (menu, hours, address)
  templates/                complete public-site templates (the first is "classic")
lib/
  supabase/                 Supabase client factories: server, browser, proxy, public, admin
  auth/                     who is signed in: getCurrentUser, requireUser
  permissions/              what they may access: requireAdmin, requireBusinessAccess, ...
  tenant/                   which business a public request is for (slug today, hostname later)
  db/                       data access: every query and mutation, plus generated DB types
  validation/               Zod schemas for every mutation's input
supabase/
  migrations/               SQL migrations: the only way the schema changes
docs/                       SPEC, ARCHITECTURE, ROADMAP
proxy.ts                    Next.js proxy (formerly middleware.ts): session refresh (M2)
```

Conventions:

- **Server Actions sit next to the route that uses them**, e.g. `app/dashboard/[businessId]/menu/actions.ts`, and stay thin. They parse input and call `lib/` functions.
- `lib/auth`, `lib/permissions`, `lib/tenant`, `lib/db` and the server-side Supabase clients start with `import 'server-only'`, so they can never end up in a browser bundle.
- Only `lib/supabase` reads Supabase environment variables.
- **Next.js 16 differs from older versions** in several ways, including `proxy.ts`, async `params`, and generated `PageProps`/`LayoutProps` types. The docs for the installed version are in `node_modules/next/dist/docs/`. Check them rather than relying on memory.

## 3. Multi-tenancy

**Model: shared database, shared schema, tenant column.** Each restaurant is a row in `businesses`, and every row of restaurant content has a `business_id`. All tenants share the same tables. Isolation comes from always scoping by `business_id`, enforced in two independent places.

The tenant is the **business**. Users are linked to businesses through `memberships`. A user can belong to several businesses, and a business can have several users. Admins aren't members of businesses; their access is platform-wide (§6).

### How isolation is enforced

| Layer | What it does | What it protects against |
|---|---|---|
| 1. `proxy.ts` | Redirects signed-out visitors away from `/dashboard` and `/admin`. | Nothing security-critical. It's a UX convenience and nothing relies on it. |
| 2. Server checks (`lib/permissions`) | Every dashboard and admin page, and every Server Action, verifies the user may access the business before touching data. | Tampered URLs, forged form fields, and direct calls to Server Actions. |
| 3. Row Level Security | Postgres only returns or changes rows the signed-in user is allowed to access. | Bugs in layer 2, and owners calling the Supabase API directly with their own session. |

Layer 3 is essential, not optional. The Supabase publishable key is public by design, so any signed-in owner can call the Supabase API directly with their own session and skip our app entirely. RLS, constraints and triggers have to make that safe on their own.

### Rules

1. **Never trust a business ID from the client.** URL params and form fields are claims, not facts. `requireBusinessAccess(businessId)` turns a claim into a verified `BusinessAccess`.
2. Tenant-scoped functions in `lib/db` take that `BusinessAccess`, not a raw ID, and scope every query by `access.businessId`. They can't be called without passing the check first.
3. Child rows are always matched on **both** their own ID and the business ID (`where id = :itemId and business_id = :businessId`). A real item ID from another tenant matches nothing.
4. The database also keeps related rows inside one tenant. For example, a composite foreign key guarantees a menu item's category belongs to the same business as the item.
5. Access failures look like "not found." We never reveal whether another tenant's business exists.
6. Anything that isn't meant to be public stays out of publicly readable tables (§7).

## 4. Database design

This is a proposal. Once approved, it becomes the first migration in `supabase/migrations/`.

### Conventions

- Primary keys are `uuid` with default `gen_random_uuid()`. Timestamps are `timestamptz`, and `updated_at` is maintained by a trigger.
- Every tenant-owned table has `business_id uuid not null references businesses on delete cascade`, and is indexed on it.
- Fixed sets of values use `text` with `check (...)` instead of Postgres enums, which are harder to change later.
- Money is stored as integer cents (`price_cents`), which avoids floating-point rounding.
- Everything is relational. JSONB is reserved for genuinely free-form configuration. The expected first use is per-site theme settings, which aren't in v1.
- Database constraints mirror the Zod validation (required fields, URL format, value ranges, text length limits). Owners can write through the Supabase API directly, so the constraints are the real limits.
- Users live in Supabase Auth (`auth.users`). We don't copy emails or names into our own tables, and admin screens read them through the Auth admin API. We'll add a `profiles` table only if we need user-editable profile fields.

### Tables

```
auth.users (Supabase Auth)
   │1          │1
   │           └────────── * memberships * ──────────┐
   │0..1                                              │1
platform_admins                                   businesses
                                                      │1
        ┌──────────────────┬────────────────────┬─────┴────────────┬────────────────────┐
        *                  *                    *                  *
  business_hours    menu_categories      business_links     business_images
                           │1
                           *
                      menu_items
```

| Table | Purpose |
|---|---|
| `platform_admins` | Users with the platform-wide ADMIN role (the founders) |
| `businesses` | One row per restaurant: the tenant |
| `memberships` | Which users can manage which business, and their role (`owner`) |
| `business_hours` | Weekly opening hours, stored as open periods |
| `menu_categories` | Menu sections such as "Pizzas" or "Drinks", in display order |
| `menu_items` | Dishes with price and availability, in display order within a category |
| `business_links` | Instagram, Facebook, online ordering and reservation URLs |
| `business_images` | Metadata for images stored in Supabase Storage |

### Proposed SQL

Tables and integrity constraints only. The helper functions and policies are in §7. The `updated_at` and admin-only-column triggers are described below the SQL.

```sql
-- Platform-wide ADMIN role. Rows are added by hand with SQL; no API or UI can grant it.
create table public.platform_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Tenants.
create table public.businesses (
  id             uuid primary key default gen_random_uuid(),
  slug           text not null unique
                   check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 63),
  name           text not null check (char_length(name) between 1 and 120),
  description    text,
  phone          text,
  address_line_1 text,
  address_line_2 text,
  city           text,
  state          text,
  zip_code       text,
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
create index on public.memberships (business_id);

-- Weekly hours as open periods. A day with no rows is closed.
-- day_of_week: 0 = Sunday ... 6 = Saturday.
-- closes_at earlier than opens_at means the period ends after midnight (18:00-02:00).
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
  name          text not null check (char_length(name) between 1 and 80),
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (id, business_id)  -- target of the composite foreign key in menu_items
);
create index on public.menu_categories (business_id, display_order);

create table public.menu_items (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  category_id   uuid not null,
  name          text not null check (char_length(name) between 1 and 120),
  description   text,
  price_cents   integer check (price_cents >= 0),  -- null = no price shown
  is_available  boolean not null default true,
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- The item's category must belong to the item's business.
  foreign key (category_id, business_id)
    references public.menu_categories (id, business_id) on delete cascade
);
create index on public.menu_items (business_id);
create index on public.menu_items (category_id, display_order);

-- At most one URL per kind per business.
create table public.business_links (
  id          uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  kind        text not null
                check (kind in ('instagram', 'facebook', 'ordering', 'reservations')),
  url         text not null check (url ~* '^https?://'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (business_id, kind)
);

-- Image metadata. The files live in the 'business-images' Storage bucket.
create table public.business_images (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references public.businesses (id) on delete cascade,
  storage_path  text not null unique,  -- '<business_id>/<random uuid>.<ext>'
  alt_text      text,
  placement     text not null default 'gallery' check (placement in ('hero', 'gallery')),
  display_order integer not null default 0,
  created_at    timestamptz not null default now(),
  check (starts_with(storage_path, business_id::text || '/'))
);
create index on public.business_images (business_id, display_order);
```

The same migration also adds:

- an `updated_at` trigger on every table that has the column;
- the `private` schema with the RLS helper functions (§7), plus RLS enabled and policies on every table;
- a `before update` trigger on `businesses` that rejects changes to `slug`, `template` or `is_published` unless the caller is an admin.

### Design notes

- **ADMIN isn't a membership role.** Admins can access every business, so the role isn't tied to any one business. It lives in `platform_admins`, and `memberships.role` only allows `owner` for now. The column is there so a business-level role such as "staff" can be added later without restructuring the table, though its policies would still need work.
- **Hours are open periods, not one row per day.** Many restaurants close between lunch and dinner (11:00–14:30, then 17:00–22:00), which one-row-per-day can't represent. A day with no rows is closed. If a business has no hours at all, the site hides the hours section instead of showing "closed" every day. The dashboard saves a whole week at once through a small SQL function, so the replacement is atomic. The function runs with the caller's permissions, so RLS still applies.
- **Publishing.** New businesses start unpublished (`is_published = false`), and anonymous visitors can't see them. Admins publish once a site is ready, and can unpublish one later, for example if a customer leaves. Changes to `slug` (which would break public URLs), `template` and `is_published` are admin-only, enforced by the trigger.
- **Links:** at most one per kind per business. URLs must start with `http://` or `https://`, which blocks `javascript:` links from ever reaching a public page. More kinds (TikTok, Yelp, …) only need the check constraint widened.
- **Images:** one row per stored file. The `storage_path` check ties every image to its own business's folder.
- **Prices:** integer cents. `null` means no price is shown (e.g. "market price"). v1 has one price per item. If pizza sizes or other variants are needed, a `menu_item_variants` table is the extension point.
- **Ordering:** `display_order` integers. A reorder saves all affected rows in one atomic SQL function call.
- **Deliberately not included yet:** a timezone column (only needed for an "open now" badge), special/holiday hours, item photos, and a domains table (§13).

## 5. Authentication

Supabase Auth handles identities, passwords, sessions and auth emails. We integrate it with `@supabase/ssr`, which stores the session in cookies so Server Components and Server Actions know who's signed in. This follows Supabase's current server-side auth guide for Next.js.

### Supabase clients (`lib/supabase/`)

| File | Key | Runs as | Used for |
|---|---|---|---|
| `server.ts` | publishable | the signed-in user (RLS applies) | Server Components and Server Actions |
| `client.ts` | publishable | the signed-in user (RLS applies) | The few Client Components that call Supabase directly (image upload) |
| `proxy.ts` | publishable | the signed-in user | `proxy.ts` only, to refresh the session cookie |
| `public.ts` | publishable | anonymous, no cookies (RLS applies) | Public site data, which can only ever see published content |
| `admin.ts` | **secret** | service role, **bypasses RLS** | Only the Auth admin API (invite users, look up emails), and only with a verified `AdminAccess` |

**Keys.** We use Supabase's **publishable** (`sb_publishable_…`) and **secret** (`sb_secret_…`) keys. The legacy `anon`/`service_role` keys stop working at the end of 2026. Variable names are in `.env.example`.

### Sessions and verification

- `proxy.ts` runs on every non-static request. It calls `supabase.auth.getClaims()` to refresh tokens that are about to expire and writes the updated cookies. It also redirects signed-out visitors from `/dashboard` and `/admin` to `/login`, but that redirect is a convenience, not a security check. The Next.js docs explicitly say the proxy isn't an authorization solution.
- On the server, identity comes from `getClaims()`, which verifies the JWT's signature. **Never use `getSession()` in server code**, because it doesn't verify the token.
- What a user may *access* is read from the database (`memberships`, `platform_admins`) on every request. Removing someone's access takes effect immediately, even while their token is still valid.

### Sign-in and accounts (proposed; see §15)

- **Email and password** login at `/login`.
- **Public sign-up is disabled** in the Supabase Auth settings, so owners can't create accounts themselves. An admin invites an owner by email with `auth.admin.inviteUserByEmail`, which creates the account, and we add the membership in the same admin action.
- Invite and password-reset emails link to `/auth/confirm`. That route verifies the one-time token, signs the user in, and sends them to a set-password page.
- Sign-out is a Server Action.
- Admins sign in the same way. After login, admins land on `/admin` and owners on `/dashboard`.

**Email delivery.** Supabase's built-in mailer only delivers to members of our Supabase team, and it's heavily rate-limited. That's fine for development but not for real owners. Before onboarding the first restaurant, we configure a custom SMTP provider in the Supabase dashboard. That's configuration only, with no code involved; Supabase Auth still sends the only emails.

## 6. Authorization

### Roles

| Role | Scope | Stored in | Can |
|---|---|---|---|
| `ADMIN` | Platform-wide | `platform_admins` | Everything: all businesses, memberships, admin-only fields |
| `OWNER` | One business per membership | `memberships.role = 'owner'` | Read and edit that business's content. Can't change its slug, template or published status, its memberships, or any other business |
| Anonymous | none | none | Read published restaurant content |

A signed-in user with no admin row and no memberships sees nothing.

### Central helpers

All authorization goes through these functions. No page or action checks roles on its own.

```ts
// lib/auth: who is signed in
getCurrentUser(): Promise<CurrentUser | null>   // verified with getClaims(); cached per request
requireUser(): Promise<CurrentUser>             // redirects to /login when signed out

// lib/permissions: what they may access
isPlatformAdmin(): Promise<boolean>
requireAdmin(): Promise<AdminAccess>                         // not found for non-admins
getAccessibleBusinesses(): Promise<BusinessSummary[]>        // admins: all; owners: their memberships
requireBusinessAccess(businessId: string): Promise<BusinessAccess>
//   resolves to { businessId, userId, role: 'admin' | 'owner', supabase }
//   not found unless the user is an admin or a member of that business
```

- The helpers are wrapped in React's `cache()`, so a layout, a page and its components share one check per request.
- `BusinessAccess` and `AdminAccess` are branded TypeScript types that only these helpers can create. Tenant-data functions in `lib/db` require a `BusinessAccess`, and admin-only functions require an `AdminAccess`. Forgetting the check is a type error, not a silent hole.

### Every page

```tsx
// app/dashboard/[businessId]/menu/page.tsx
export default async function MenuPage({ params }: PageProps<'/dashboard/[businessId]/menu'>) {
  const { businessId } = await params;
  const access = await requireBusinessAccess(businessId); // the security boundary
  const menu = await getMenuForEditing(access);           // lib/db, scoped to access.businessId
  return <MenuEditor businessId={access.businessId} menu={menu} />;
}
```

Layouts call the helpers too (for navigation and the business name), but **pages and actions never rely on a layout's check**. Layouts don't re-run on every navigation, and Server Actions don't go through layouts at all.

### Every Server Action

A Server Action is a public HTTP endpoint that anyone can call with any arguments. Every action follows the same five steps:

```ts
'use server';

export async function updateMenuItem(_prev: ActionResult, formData: FormData): Promise<ActionResult> {
  const parsed = updateMenuItemSchema.safeParse(Object.fromEntries(formData)); // 1. validate
  if (!parsed.success) return validationError(parsed.error);

  const access = await requireBusinessAccess(parsed.data.businessId);         // 2. authorize
  const result = await saveMenuItem(access, parsed.data);                     // 3. write via lib/db
  if (!result.ok) return result;

  refreshPublicSite(access.businessId);                                       // 4. refresh the site
  return { ok: true };                                                        // 5. typed result
}
```

Expected failures, such as validation errors or a missing row, come back as values the form can display. Unexpected errors are logged on the server, and the user sees a generic message, never a raw database error.

### When a check fails

| Situation | Pages | Server Actions |
|---|---|---|
| Not signed in | Redirect to `/login`, then back afterwards | Rejected before any data is read or written |
| No access to that business | 404 | Rejected the same way |
| Non-admin on `/admin` | 404 | Rejected the same way |

## 7. Row Level Security strategy

**Every table in the `public` schema has RLS enabled, with no exceptions.** With RLS on, Postgres returns and changes nothing unless a policy allows it, so every access path has to be granted explicitly.

### Helper functions

Policies call three small SQL functions in a `private` schema, which isn't exposed through the Supabase API. They're `security definer` with an empty `search_path`, so they can read `memberships` and `platform_admins` without recursive RLS checks.

| Function | Returns true when |
|---|---|
| `private.is_platform_admin()` | the current user has a `platform_admins` row |
| `private.can_manage_business(business_id)` | the current user is an admin, or has a membership for that business |
| `private.is_published_business(business_id)` | that business is published |

### Policy matrix

| Table | Anonymous | Owner | Admin |
|---|---|---|---|
| `businesses` | read published | read and update their own (not slug, template or published) | everything |
| `business_hours`, `menu_categories`, `menu_items`, `business_links`, `business_images` | read rows of published businesses | read and write rows of their own businesses | everything |
| `memberships` | none | read their own | everything |
| `platform_admins` | none | read only their own row, if any (this is how the app checks admin status) | read only their own row. Rows are added and removed with SQL only |
| Storage bucket `business-images` | read (public bucket) | upload, replace and delete inside their business's folder | everything |

Creating and deleting businesses is admin-only. Every tenant content table follows the same pattern:

```sql
alter table public.menu_items enable row level security;

create policy "Anyone can read menu items of published businesses"
  on public.menu_items for select to anon, authenticated
  using (private.is_published_business(business_id));

create policy "Members and admins can manage menu items"
  on public.menu_items for all to authenticated
  using (private.can_manage_business(business_id))
  with check (private.can_manage_business(business_id));
```

`with check` also stops anyone from moving a row into a business they don't belong to.

### What RLS can't express, and how we cover it

- **Owners can't change `slug`, `template` or `is_published`.** RLS works on rows, not columns. A `before update` trigger on `businesses` rejects changes to those columns unless the caller is an admin.
- **Cross-tenant references.** The composite foreign key on `menu_items` and the `storage_path` check on `business_images` keep related rows inside one tenant.

### Rules for every future migration

- **A new table gets RLS enabled and its policies in the same migration.** A tenant table without policies is a bug.
- **Public read policies expose every column of matching rows.** Never add internal data (notes, billing status, lead scores) to `businesses` or any other publicly readable table. Put it in a separate admin-only table.
- Follow Supabase's RLS performance advice: write `(select auth.uid())` rather than `auth.uid()`, give every policy an explicit role (`to anon` / `to authenticated`), and index the columns policies filter on.
- **The secret key bypasses RLS.** It's used only in `lib/supabase/admin.ts`, only behind `requireAdmin()`, and only for Auth admin calls, never for ordinary data access.
- RLS has automated tests (§12) that run in CI.

## 8. Public website rendering

Route: `app/sites/[slug]/page.tsx`, a Server Component.

1. **Resolve the tenant** (`lib/tenant`): slug → published business. Later this also covers hostname → business (§13).
2. **Load the site** (`lib/db`): a single query using Supabase nested selects returns the business with its hours, categories and items, links and images, each sorted by `display_order`. It uses the cookie-less public client, so RLS guarantees only published data comes back.
3. **Render** the business's template, `components/templates/classic`. Templates are presentational: they receive one typed data object and never fetch anything.
4. **Unknown slug or unpublished business** → `notFound()` (404).
5. **Metadata:** `generateMetadata` uses the same per-request-cached loader for the page title, description and social preview image.

**Freshness.** In v1 the route explicitly opts out of caching and renders on every request directly from Postgres, so a saved change appears on the next page load. The opt-out is required. By default, Next.js caches data fetched before any request-time API (cookies, headers) indefinitely, and the public client uses neither. Without the opt-out, a site would keep showing old content. Development always renders on demand, so the problem only appears in production builds; M3 tests against one. When traffic justifies caching, we'll enable Next.js Cache Components: each site's data is cached with a per-business `cacheTag`, and the dashboard's Server Actions call `updateTag` for that business after each save. Every write path already calls `refreshPublicSite(businessId)`, so adding caching is a change in one place.

**Safety.** Restaurant content is rendered as text, and React escapes it. v1 has no raw HTML. Links are limited to `http(s)` by both validation and a database constraint.

**Templates.** `businesses.template` names the template, and only `classic` exists. A template is a React component that takes the site data object. Adding one means a new component plus a wider check constraint.

## 9. Customer dashboard

| Route | Purpose |
|---|---|
| `/dashboard` | Lists the businesses the user can access, and goes straight to the business when there's only one |
| `/dashboard/[businessId]` | Overview: published status, link to the public site, shortcuts |
| `…/business` | Name, description, phone, address |
| `…/hours` | Each day is either closed or has one or more open periods |
| `…/menu` | Categories and items: create, edit, delete, reorder, prices, availability |
| `…/photos` | Upload, replace, reorder and delete; hero or gallery; alt text |
| `…/links` | Instagram, Facebook, ordering URL, reservation URL |

- The business ID is part of the URL. An owner with several restaurants can switch between them, links are shareable, and admins use these same screens for any business instead of a duplicate admin editor (§10).
- `app/dashboard/[businessId]/layout.tsx` checks access for the navigation, and each page checks again (§6).
- Each page is a Server Component that loads data and renders a small Client Component form. The form submits to a Server Action with React's `useActionState` and shows field errors and a "Saved" state.
- After a successful save, the action refreshes both the dashboard view and the public site.
- The UI stays plain: Tailwind plus a few shared form components. We won't adopt a component library unless we decide it's needed.

## 10. Admin dashboard

| Route | Purpose |
|---|---|
| `/admin` | Entry point; shows the businesses list |
| `/admin/businesses` | All businesses: name, slug, published status, owners |
| `/admin/businesses/new` | Create a business (name, slug) |
| `/admin/businesses/[businessId]` | Admin-only settings (slug, template, published), members (invite an owner, remove access), and a link to edit content |
| `/admin/customers` | Restaurant owner accounts and the businesses each one can access |

- `app/admin/layout.tsx` calls `requireAdmin()`, and every admin page and action calls it again.
- **Content editing isn't duplicated.** "Edit content" links to `/dashboard/[businessId]/…`, which admins can open because `requireBusinessAccess` allows admins. The admin area only contains what owners can't do.
- **Inviting an owner** is the only place the secret key is used: an admin-only `lib/db` function (which requires `AdminAccess`) calls `lib/supabase/admin.ts` → `auth.admin.inviteUserByEmail(…)`, then inserts the membership.
- No CRM, lead or billing features.

## 11. File storage

- **One public-read bucket, `business-images`.** Restaurant photos appear on public websites, and file names are random UUIDs that can't be guessed.
- **Object path:** `<business_id>/<random uuid>.<ext>`. The first folder identifies the tenant. Storage policies apply `private.can_manage_business` to it, so only an admin or a member of that business can write or delete objects there.
- **Bucket limits:** JPEG, PNG and WebP only, with a maximum file size (proposed: 5 MB).
- **Upload flow:**
  1. The browser uploads the file straight to Storage using the user's session. This avoids request-size limits on Server Actions and Vercel functions, and Storage policies reject any path outside the user's own businesses.
  2. A Server Action (validate → `requireBusinessAccess` → insert) records the `business_images` row. The database checks that `storage_path` starts with the business's ID.
  3. The public site is refreshed.
- **Delete:** a Server Action removes the database row and then the stored file.
- **Display:** `next/image`, with the Supabase Storage host allowed in `next.config.ts`.
- The database stores paths, never image data. Rarely, an upload succeeds but saving the row fails, leaving an orphaned file. That's harmless, and a cleanup script can be added later if needed.

## 12. Testing strategy

**Tenant isolation tests come first.** They're written alongside the code they protect, starting in Milestone 1, and run in CI on every push.

| Layer | Tool | Covers |
|---|---|---|
| Database | pgTAP, run by `supabase test db` against the local Supabase stack (Docker) | RLS policies, triggers and constraints, exercised as anonymous, owner A, owner B and admin |
| End to end | Playwright against the local app and local Supabase, with seed data | Route protection, cross-tenant URLs, edit → public site |
| Unit | Vitest, only if enough pure logic appears (e.g. hours formatting) | Added only when there's something worth testing |

**Seed data** (`supabase/seed.sql`): two businesses, A ("Joe's Pizza") and B ("Thai Garden"), one owner for each, one admin, and sample hours, menu and links.

| # | Requirement | How it's tested |
|---|---|---|
| 1 | Unauthenticated users can't access `/dashboard` | E2E: redirected to `/login` |
| 2 | Unauthenticated users can't access `/admin` | E2E: redirected to `/login` |
| 3 | OWNER can't access `/admin` | E2E: 404, and admin actions are rejected |
| 4 | Owner of A can't access B | DB: for every tenant table, owner A can't read B's unpublished data, can't write any of B's rows, can't move rows into B, and can't reference B's rows. E2E: `/dashboard/<B's id>/…` returns 404 |
| 5 | ADMIN can access all businesses | DB and E2E |
| 6 | Restaurant updates persist correctly | E2E: edit in the dashboard, reload, the value is still there |
| 7 | Public site shows current database values | E2E: change a value, reload `/sites/<slug>`, see it. An unpublished business returns 404 |

Additional database tests:

- Anonymous users read only published content, and never `memberships` or `platform_admins`.
- Owners can't change slug, template or published status, can't create memberships, and can't grant themselves admin.
- Storage writes outside a user's own business folder fail.

## 13. Future: custom domains

**Not implemented.** Goal: `joespizza.com` serves Joe's Pizza's site.

- **Table:** `business_domains (id, business_id, hostname unique, is_primary, verified_at, created_at)`, managed by admins.
- **Routing:** `proxy.ts` reads the request's `Host`. Our own hosts (the app domain and Vercel preview URLs) pass through unchanged. Any other host is looked up in `business_domains` and **rewritten** internally to `/sites/[slug]`, so the visitor still sees `joespizza.com` while the same page and template render. The proxy runs on every request, so the lookup gets a short-lived cache. Unknown hosts get a 404.
- **Vercel:** when an admin attaches a domain, we add it to the Vercel project through the Vercel API. The owner points DNS at Vercel, and Vercel issues the TLS certificate. An easy first step is subdomains of a domain we own (e.g. `joes-pizza.<our-domain>`) through a wildcard domain. Slugs are capped at 63 characters, so every slug is a valid subdomain label.
- **Separation:** the dashboard and admin stay on the app domain. Auth cookies are never set on restaurant domains, and public sites never need a session.
- **SEO:** once a business has a primary domain, `/sites/[slug]` sets its canonical URL to that domain or redirects to it.

That's why tenant resolution lives in `lib/tenant`: today it maps a slug to a business, and later it'll also map a hostname. Everything after it stays the same.

## 14. Future: lead intelligence integration

**Not implemented.** A future system will discover restaurants, score them as prospects, and help the founders reach out. It stays separate from the website platform:

- **Separate data.** Leads live in their own schema (e.g. `intel`) or their own database, never in `businesses` or other tenant tables. A lead isn't a tenant, and `businesses` is partly public (§7).
- **Separate process.** Discovery and scoring can run outside the Next.js app, as scheduled jobs or a separate worker in any language. They don't need access to tenant tables.
- **One integration point: converting a lead.** When a prospect becomes a customer, an admin action creates the `businesses` row, optionally pre-filled from the lead (name, phone, address, hours), and records the new business ID on the lead. From then on the business is managed only through this platform.
- **Admin-only visibility.** If lead data appears in `/admin`, it's read through admin-only policies, or with the secret key behind `requireAdmin()`. Owners and anonymous visitors can never reach it.
- Adding this system won't require changes to the current design. The one rule today: **don't add prospect or lead fields to the platform's tables.**

## 15. Decisions pending review

These are proposals, not settled choices. Each one is easy to change before Milestone 1 and harder afterwards.

| # | Decision | Proposal | Main alternative |
|---|---|---|---|
| 1 | Dashboard URLs | `/dashboard/[businessId]/menu`: supports owners with several restaurants and lets admins reuse the owner screens | `/dashboard/menu`, assuming one business per owner |
| 2 | How ADMIN is stored | `platform_admins` table (platform-wide); `memberships.role` is `owner` only | ADMIN as a membership role, or a flag in Supabase Auth `app_metadata` |
| 3 | Hours model | Several open periods per day; no rows means closed | One row per day with `open_time`, `close_time`, `closed` (can't represent lunch/dinner splits) |
| 4 | Publishing | `is_published` flag; slug, template and publishing are admin-only | Owners publish their own sites |
| 5 | Login method | Email and password, invite-only, sign-up disabled | Passwordless email links or codes |
| 6 | Pricing | Integer cents, one price per item in v1 | Size/variant pricing from day one |
| 7 | Test tooling | Supabase CLI local stack (Docker) + pgTAP + Playwright | Test against a hosted dev project; Vitest only |
