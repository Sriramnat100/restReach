# restReach Roadmap

**Status:** approved 2026-10-01 · M0 and M1 done · **Last updated:** 2026-10-01

This is the build order for the first release. Each milestone ends in a working, tested state and gets reviewed before the next one starts. The design behind it is in [ARCHITECTURE.md](./ARCHITECTURE.md).

**Every milestone finishes with:**
- `npm run lint`, `npm run typecheck` and all tests passing
- docs updated to match what was built
- review and approval before moving on

Dependencies are listed per milestone so the package list only grows with a concrete reason.

---

## M0: Foundation ✅

- Next.js 16 + TypeScript + Tailwind CSS + ESLint scaffold (App Router)
- Folder structure, `.env.example`, README
- SPEC, ARCHITECTURE (schema, auth, authorization, RLS proposals) and this roadmap

## M1: Database and tenant isolation ✅

**Goal:** the schema exists locally, and the database itself provably keeps tenants apart.

- [x] Supabase CLI 2.119 as a pinned dev dependency; local stack with `npm run db:start` (Docker). Unused services (realtime, edge functions, log analytics) are turned off
- [x] First migration (`supabase/migrations/20261001215117_initial_schema.sql`):
  - tables, constraints and indexes
  - `updated_at` triggers and the `private` helper functions
  - RLS on every table, with one policy per role and action
  - the admin-only-fields trigger
  - atomic functions for replacing hours and reordering categories, items and images
- [x] `supabase/seed.sql`:
  - Joe's Pizza and Thai Garden (published)
  - Pasta House (unpublished draft)
  - an owner login for each restaurant owner and an admin login
  - sample hours (including split shifts), menus and links
- [x] Generated types in `lib/db/database.types.ts` (`npm run db:types`)
- [x] **74 pgTAP tests** in two files:
  - every table, checked as anonymous, outsider, owner A, owner B and admin
  - admin-only fields, edit functions and constraints
  - a guard that fails if any table lacks RLS
- [x] Proved the tests can fail: four deliberately broken rules were each caught
- [x] Checked end to end through the real local API: sign-in works for the dev logins, and each user sees and edits only what they should
- [x] CI workflow (`.github/workflows/ci.yml`): lint, typecheck, database tests, and a check that generated types are up to date. It runs on pushes to `main` and on pull requests; the first run happens once this milestone is pushed

Adds: `supabase` (dev)

## M2: Authentication and protected areas

**Goal:** people can sign in, and every protected route is enforced on the server.

**First:** decide the login method (password or passwordless; ARCHITECTURE §15).

- `lib/supabase/` clients (server, browser, proxy, public, admin) using the publishable and secret keys
- `proxy.ts`: session refresh with `getClaims()`, plus optimistic redirects for `/dashboard` and `/admin`
- `/login`, sign out, `/auth/confirm`, and the set-password page; Supabase Auth configured with sign-up disabled
- `lib/auth` (`getCurrentUser`, `requireUser`) and `lib/permissions` (`isPlatformAdmin`, `requireAdmin`, `getAccessibleBusinesses`, `requireBusinessAccess`, plus the `BusinessAccess`/`AdminAccess` types)
- Page shells only: `/dashboard` (business list), `/dashboard/[businessId]` (layout and overview), `/admin` (layout and placeholder)
- **E2E tests:** signed-out users are sent from `/dashboard` and `/admin` to `/login`; an owner gets 404 on `/admin`; owner A gets 404 on `/dashboard/<B>`; an admin can open any business

Adds: `@supabase/supabase-js`, `@supabase/ssr`, `@playwright/test` (dev)

## M3: Public restaurant site

**Goal:** `/sites/joes-pizza` renders entirely from the database.

- `lib/tenant`: slug → published business
- Public site loader: one nested query using the public (anonymous) client
- `classic` template: hero, name, description, menu, hours, address and phone, ordering and reservation buttons, social links, and images if present
- 404 for unknown or unpublished slugs; `generateMetadata` for title, description and social preview
- The route explicitly opts out of caching, so changes show on the next load (ARCHITECTURE §8)
- Connect the repo to Vercel for preview deployments
- **E2E tests**, run against a production build (`next build && next start`) because development never caches: the site shows seeded values; a value changed in the database shows after a reload; an unpublished business returns 404

## M4: Owner dashboard (business info, hours, links)

**Goal:** owners can edit their basic information, and it goes live on save.

- The Server Action pattern from ARCHITECTURE §6: validate → authorize → write via `lib/db` → refresh public site → typed result
- Shared form components (field, error message, save button with pending and "Saved" states)
- Business info form, weekly hours editor (closed or several periods per day), links form
- **Tests:** edits persist and appear on the public site; a business ID belonging to another tenant is rejected; invalid input such as a `javascript:` URL or a bad time range is rejected

Adds: `zod`

## M5: Menu management

**Goal:** owners manage their full menu.

- Categories: create, rename, reorder, delete (with a confirmation that its items will be deleted too)
- Items: create, edit, delete, reorder, move to another category, set price, toggle availability
- **Tests:** CRUD persists; reorders are atomic; an item can't be moved into another business's category; another tenant's item IDs are rejected

## M6: Photos

**Goal:** owners manage restaurant images.

- Migration: `business-images` bucket (allowed types, size limit) and Storage policies
- Browser upload straight to Storage, then a Server Action records the row; hero vs gallery, alt text, reorder, delete
- `next/image` configured for the Supabase Storage host
- **Tests:** owner A can't upload to, overwrite or delete files in B's folder; image rows can't point at another business's path

## M7: Admin dashboard

**Goal:** the founders can onboard and manage restaurants without SQL.

- `/admin/businesses`: list, create, view; edit slug, template and published status
- Members: invite an owner by email (Auth admin API, secret key), list members, remove access
- `/admin/customers`: owner accounts and the businesses they belong to
- "Edit content" links to the shared dashboard screens
- **Tests:** owners are rejected from every admin page and action; an admin can create, publish and invite; a removed owner loses access immediately

## M8: Production launch

**Goal:** the first real restaurant is live.

- Hosted Supabase production project with migrations applied (seed data stays local)
- Auth configuration: custom SMTP, sign-up disabled, redirect URL allow-list, password rules
- Vercel production project with environment variables; check that the secret key is server-only
- Error and not-found pages; run Supabase's security and performance advisors
- Onboard the first restaurant end to end

---

## Later (not scheduled)

Custom domains (ARCHITECTURE §13), lead intelligence (ARCHITECTURE §14), public-site caching with `cacheTag`/`updateTag`, special and holiday hours, item variants and photos, more templates and theme settings, unpublished-site preview for owners.
