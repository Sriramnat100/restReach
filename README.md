# restReach

A multi-tenant website platform for local restaurants. Owners log in, edit their hours, menu, prices, photos and links, and their public website updates immediately. All content lives in Postgres, so there are no per-restaurant code changes or redeploys.

> **Status: Milestone 0 (foundation).** This repository contains the project scaffold and the architecture proposal. There are no application features, database tables or Supabase integration yet. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Documentation

| Doc | Contents |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | Product goal, personas, features, scope, non-goals, main workflows |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Multi-tenancy, database, authentication, authorization, RLS, rendering, storage, testing, future plans |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestone-by-milestone implementation plan |

New to the project? Read SPEC first, then ARCHITECTURE.

## Tech stack

- **Next.js 16** (App Router), **React 19**, **TypeScript**, **Tailwind CSS 4**, **ESLint 9**
- **Supabase** for Postgres, Auth and Storage (planned for Milestones 1 and 2)
- **Vercel** for hosting (planned)

It's one Next.js app backed by one Supabase project: no monorepo, no microservices.

## Getting started

Prerequisites: Node.js 20.9 or newer and npm. From Milestone 1 you'll also need Docker for the local Supabase stack.

```bash
npm install
cp .env.example .env.local   # nothing reads these values yet
npm run dev                  # http://localhost:3000
```

## Scripts

| Command | What it does |
|---|---|
| `npm run dev` | Start the development server |
| `npm run build` | Create a production build |
| `npm run start` | Serve the production build |
| `npm run lint` | Run ESLint |
| `npm run typecheck` | Generate Next.js route types, then run `tsc --noEmit` |

Run `npm run lint && npm run typecheck` before every commit.

## Project structure

```
app/          routes: sites/[slug] (public), dashboard/ (owners), admin/ (admins)
components/   UI grouped by area; templates/ holds the public-site templates
lib/          server-side logic: supabase/, auth/, permissions/, tenant/, db/, validation/
supabase/     SQL migrations
docs/         spec, architecture, roadmap
```

Most folders only hold a `.gitkeep` placeholder for now. [ARCHITECTURE.md §2](docs/ARCHITECTURE.md#2-code-organization) explains what belongs in each one.

## Ground rules

1. **Tenant isolation comes first.** Never trust a business ID from the browser. Server code verifies access through the central permission helpers, and Postgres Row Level Security enforces it again.
2. **Every table has Row Level Security. Every Server Action validates, authorizes, then writes.**
3. **Secrets stay on the server and out of Git.** Only `.env.example` is committed.
4. **Keep it simple.** Server Components by default, and no new dependencies or abstractions without a concrete need.

Details are in [ARCHITECTURE.md](docs/ARCHITECTURE.md).
