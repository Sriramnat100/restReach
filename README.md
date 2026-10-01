# restReach

A multi-tenant website platform for local restaurants. Owners log in, edit their hours, menu, prices, photos and links, and their public website updates immediately. All content lives in Postgres, so there are no per-restaurant code changes or redeploys.

> **Status: Milestone 1 done.** The database exists locally: schema, Row Level Security, sample data and 74 tenant-isolation tests. The web app has no features yet; login comes next in Milestone 2. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Documentation

| Doc | Contents |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | Product goal, personas, features, scope, non-goals, main workflows |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Multi-tenancy, database, authentication, authorization, RLS, rendering, storage, testing, future plans |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestone-by-milestone implementation plan |

New to the project? Read SPEC first, then ARCHITECTURE.

## Tech stack

- **Next.js 16** (App Router), **React 19**, **TypeScript**, **Tailwind CSS 4**, **ESLint 9**
- **Supabase** for Postgres, Auth and Storage. The database runs locally through the Supabase CLI; the app connects to it starting in Milestone 2
- **Vercel** for hosting (planned)

It's one Next.js app backed by one Supabase project: no monorepo, no microservices.

## Getting started

Prerequisites: Node.js 20.9 or newer, npm, and Docker Desktop (running) for the local Supabase stack.

```bash
npm install
npm run db:start   # local Supabase: applies migrations and loads sample data
npm run dev        # http://localhost:3000
```

The first `db:start` downloads Supabase's Docker images, so it takes a few minutes. Once it's running:

- **Supabase Studio** (browse tables, run SQL): http://127.0.0.1:54323
- **Sample data:** Joe's Pizza, Thai Garden, and Pasta House (an unpublished draft). Dev logins for an admin and two owners are listed at the top of [supabase/seed.sql](supabase/seed.sql)
- `npx supabase status` prints the local API URL and keys for `.env.local`. Nothing reads them until Milestone 2

`npm run db:stop` shuts the stack down; your local data is kept until the next `db:reset`.

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Start the development server |
| `npm run build` | Create a production build |
| `npm run start` | Serve the production build |
| `npm run lint` | Run ESLint |
| `npm run typecheck` | Generate Next.js route types, then run `tsc --noEmit` |
| `npm run db:start` / `db:stop` | Start or stop the local Supabase stack |
| `npm run db:reset` | Rebuild the local database from the migrations and seed data |
| `npm run db:test` | Run the database tests (RLS and tenant isolation) |
| `npm run db:types` | Regenerate `lib/db/database.types.ts` from the local schema |

Run `npm run lint && npm run typecheck && npm run db:test` before every commit. CI runs the same checks on pull requests and pushes to `main`.

**Changing the database:** add a new migration with `npx supabase migration new <name>` (never edit one that's been applied). Then run `npm run db:reset`, `npm run db:test` and `npm run db:types`, and add tests for any new table or policy.

## Project structure

```
app/          routes: sites/[slug] (public), dashboard/ (owners), admin/ (admins)
components/   UI grouped by area; templates/ holds the public-site templates
lib/          server-side logic: supabase/, auth/, permissions/, tenant/, db/, validation/
supabase/     migrations, database tests, seed data, local config
docs/         spec, architecture, roadmap
```

Most `app/`, `components/` and `lib/` folders only hold a `.gitkeep` placeholder for now. [ARCHITECTURE.md §2](docs/ARCHITECTURE.md#2-code-organization) explains what belongs in each one.

## Ground rules

1. **Tenant isolation comes first.** Never trust a business ID from the browser. Server code verifies access through the central permission helpers, and Postgres Row Level Security enforces it again.
2. **Every table has Row Level Security. Every Server Action validates, authorizes, then writes.**
3. **Secrets stay on the server and out of Git.** Only `.env.example` is committed.
4. **Keep it simple.** Server Components by default, and no new dependencies or abstractions without a concrete need.

Details are in [ARCHITECTURE.md](docs/ARCHITECTURE.md).
