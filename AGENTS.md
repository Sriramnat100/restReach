<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# restReach project notes

- Read `docs/SPEC.md`, `docs/ARCHITECTURE.md` and `docs/ROADMAP.md` before changing code. Only build the milestone you were asked to build.
- The tenant-isolation, authorization and Row Level Security rules in `docs/ARCHITECTURE.md` (sections 3, 6 and 7) are mandatory.
- Don't add dependencies or abstractions without a concrete, current need.
- Database changes go in a new file in `supabase/migrations/` (never edit an applied migration), with pgTAP tests in `supabase/tests/` for every new table or policy. Then run `npm run db:reset`, `npm run db:test` and `npm run db:types`.
- Run `npm run lint`, `npm run typecheck` and `npm run db:test` before committing.
