# restReach Product Spec

**Status:** draft for review (Milestone 0) · **Last updated:** 2026-10-01

How the system is built is covered in [ARCHITECTURE.md](./ARCHITECTURE.md). The build order is in [ROADMAP.md](./ROADMAP.md).

## 1. Product goal

restReach runs websites for local restaurants. Restaurant owners log in to a simple dashboard and edit their business information: hours, menu, prices, photos and links. When they save, their public website changes right away. No developers, Git commits or redeploys are involved.

Every restaurant (Joe's Pizza, Thai Garden, Pasta House, …) uses the same application and codebase. Restaurant content lives in PostgreSQL, and every public site is rendered from the database.

The platform has two sides:

1. **Internal admin platform.** The founders use it to onboard restaurants, manage their sites and manage owner accounts.
2. **Customer dashboard.** Restaurant owners use it to manage their own public website.

## 2. Personas

| Persona | Role | Who they are | What they need |
|---|---|---|---|
| Platform admin | `ADMIN` | The two founders. | See and manage every restaurant, set up new sites, invite owners, and fix things for owners when asked. |
| Restaurant owner | `OWNER` | A busy owner or manager, usually not technical, often on a phone. | Change a price, update hours or mark a dish unavailable in under a minute, and trust that it's live. Must never see another restaurant's data. |
| Site visitor | none (anonymous) | A diner, usually on a phone. | Quickly find the menu, hours, address and phone number, and a way to order or book. |

## 3. Core features (long-term product)

### Public restaurant website
- One reusable template, filled in from each restaurant's data.
- Hero section with a photo, the business name and a description.
- Menu: categories containing items, each with a description and price. Items marked unavailable are shown as unavailable.
- Opening hours, address and phone number.
- "Order online" and "Reserve a table" buttons when the restaurant has those links.
- Instagram and Facebook links.
- Restaurant photos.

### Customer dashboard (`OWNER`)
- **Business information:** name, description, phone and address.
- **Hours:** weekly opening hours for each day.
- **Menu:** create, rename, reorder and delete categories; add, edit, delete and reorder items; change prices; mark items unavailable.
- **Photos:** upload, replace, reorder and delete images; choose the hero image.
- **Links:** Instagram, Facebook, online ordering URL and reservation URL.

### Internal admin (`ADMIN`)
- List, view, create and edit businesses, including admin-only settings: URL slug, template and published status.
- See which users can access each business; invite owners and remove access.
- Edit any business's content on the owner's behalf.

## 4. Current scope

**Done so far (Milestones 0–1):** project scaffold, documentation, and the database: schema, security rules, sample data and tenant-isolation tests, running locally. There are no user-facing features yet.

**First release (MVP),** Milestones 1–8 in [ROADMAP.md](./ROADMAP.md):
- Database schema with Row Level Security and automated tenant-isolation tests
- Login for admins and owners (owner accounts are created by invitation only)
- Public sites at `/sites/[slug]` using one template
- Owner dashboard: business info, hours, links, menu and photos
- Admin dashboard: businesses, owners and publishing
- Production deployment on Vercel with a hosted Supabase project

## 5. Explicit non-goals (for now)

We're not building any of the following. ARCHITECTURE.md only describes how a few of them could fit later.

- **Lead intelligence:** discovering, scoring or contacting restaurants. This is a separate future system.
- **AI** website generation or AI-written content.
- **Custom domains.** The approach is documented, but nothing is implemented.
- **Payments, subscriptions or billing** (no Stripe).
- **Analytics or tracking.**
- **Email infrastructure** such as newsletters, notifications or transactional email. The only email sent is Supabase Auth's own invite and password-reset messages.
- **CRM features** such as notes, pipelines or tasks.
- **Multiple templates or theme customization.**
- **Processing orders or reservations.** We only link to the restaurant's existing providers.
- Special or holiday hours, menu item variants (sizes, add-ons), dietary tags, and multiple languages.
- Self-serve sign-up for restaurant owners.
- Draft/preview workflow for content edits.
- Native mobile apps, microservices, a monorepo, or Python services.

## 6. Main workflows

### 6.1 Onboard a restaurant (admin)
1. An admin creates the business with a name and URL slug, e.g. `joes-pizza`.
2. The admin fills in the business information, hours, menu, links and photos, using the same screens owners use.
3. The admin invites the owner by email. This creates the owner's account and gives it access to that business.
4. The owner opens the invite link, sets a password and lands on their dashboard.
5. The admin publishes the business, and `/sites/joes-pizza` goes live.

### 6.2 Owner updates their site
1. The owner logs in and opens their restaurant in the dashboard.
2. They make a change, for example raising a price or marking a dish unavailable, and save.
3. The server validates the input and confirms the owner belongs to that business.
4. The change is written to Postgres.
5. The next visit to the public site shows the change. No deploy is involved.

### 6.3 Visitor views a restaurant site
1. A visitor opens `/sites/joes-pizza` (later, `joespizza.com`).
2. The server finds the published business for that slug and loads its content.
3. The page renders with current data. Unknown or unpublished restaurants return "not found".

### 6.4 Admin helps an owner
1. An admin finds the business in `/admin`.
2. They open its content screens and make the change for the owner.
3. They can see who has access to the business, invite another owner, or remove someone's access.

## 7. Product rules

- **Tenant isolation is the top requirement.** An owner can only see and change businesses they belong to. This is enforced on the server and in the database, not just by hiding things in the UI.
- **Saved means live.** Content edits go live when saved. Making a restaurant's site public for the first time (publishing) is an admin action.
- **Content lives in the database**, never in source files, so editing content never requires a commit or a deploy.
- **Simple over clever.** An owner should be able to use every screen without training.
