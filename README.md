# APAAR Sentinel

Fresh React + TypeScript + Vite application for an academic student-data management prototype. This project does not reuse prior repositories or deployments.

## Included
- Responsive institutional dashboard, student records, institution directory, verification centre, CSV upload, analytics/CSV summary export, audit log.
- Supabase Auth sign-in, registration, password reset.
- PostgreSQL schema, foreign keys, indexes, RLS, profile bootstrap, timestamps and database-triggered audit events.
- CSV preview, required-column checks, duplicate checks and import summary.
- Empty states and no fabricated database metrics.

## Requirements
Node.js 20+ recommended; a Supabase project.

## Run locally
1. Extract this folder and open a terminal in it.
2. `npm install`
3. Copy `.env.example` to `.env`.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` using the Supabase project URL and publishable/anon key. Never use a service-role key in the browser.
5. In Supabase SQL Editor, run `supabase/migrations/001_initial_schema.sql`.
6. `npm run dev`, then open the local URL printed by Vite.

If environment variables are missing, the app displays a setup page rather than fake data.

## First administrator setup
1. Register through the app. Supabase may require email confirmation depending on project settings.
2. Create an institution using an authorized admin workflow. For the initial academic prototype bootstrap, you can create the first institution via Supabase SQL Editor.
3. Find your account ID in Supabase Authentication > Users.
4. After creating an institution, assign your account a role and institution using SQL Editor. Example (replace IDs):
   `update public.profiles set role='administrator', institution_id=NULL where id='YOUR-AUTH-USER-UUID';`
5. Create/assign institution data managers through a trusted admin-only process. The frontend intentionally does not let users self-assign privileged roles.

The SQL migration enables RLS. A fresh signup gets the `viewer` role. For a production deployment, build a dedicated admin edge function/server-side workflow to manage profiles, invite users, and assign institutions. Do not expose service-role credentials.

## Important implementation notes
- This is an academic prototype, not an official APAAR/AICTE/DigiLocker integration.
- APAAR ID validation is a project-level non-empty/duplicate check only; no official format is claimed.
- The CSV import currently inserts valid rows in a single bulk insert and records upload-job results. For strict all-or-nothing guarantees and concurrency-safe duplicate handling, move the import into a PostgreSQL RPC/Edge Function transaction that also writes issue rows.
- PDF printing can be done from the browser using Print > Save as PDF; the analytics summary exports to CSV. Dedicated server-generated PDF output and a transactional RPC are production hardening tasks.
- Some privileged actions (profile/role administration and richer audit-event coverage for sign-ins and report generation) require a trusted server-side admin workflow before production use.
- Use synthetic data only in demos.

## Deploy
Build with `npm run build`. Deploy the generated `dist/` folder using the hosting provider's Vite/static-site workflow. Configure the same environment variables in deployment settings and set SPA fallback rewrites to `index.html`. Configure Supabase Auth redirect URLs for the local and deployed origins.
