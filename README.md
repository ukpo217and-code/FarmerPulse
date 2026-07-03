# FarmerPulse â€” Supabase schema snapshot (2026-07-03)

## What this is

This is a **reverse-engineered snapshot** of the live schema on project
`jmltamnqlqewwsqvcvme` (FarmerPulse, `eu-central-1`), reconstructed from
`pg_catalog`/`information_schema` via SQL introspection â€” not a real
migration history. It's a starting point for putting this database under
version control, not a substitute for one.

Apply in order: `0001` â†’ `0008`. Each file is idempotent-ish but not
fully guarded (some `CREATE POLICY` / `CREATE VIEW` statements will error
on a database that already has them â€” that's expected if you're comparing
against the live project rather than seeding a fresh one).

## Resolved this session

**Two triggers on `auth.users` merged into one generic flow.**
`0007` originally hardcoded a single email
(`ukpoju.andrew@gmail.com`) into the bootstrap trigger. `0008` replaces
it with `app.bootstrap_from_invitation()` plus a real `invitations`
table (`email`, `organization_id`, `org_role`, `platform_role`,
`expires_at`, `status`). To onboard anyone â€” including future coalition
partners â€” insert a row into `invitations`, they sign up with that
email via Supabase Auth, and the trigger does the rest. Andy's own
`platform_admin` invitation is re-seeded through this path in `0008`.

**Fixed a live production-breaking permissions bug.**
`authenticated` had `EXECUTE` on the individual `app.*` helper
functions but no `USAGE` on the `app` schema itself. Every RLS policy
that calls `app.is_platform_admin()`, `app.current_actor_id()`, etc.
would have thrown a permission error for any real logged-in user â€”
this was invisible to the Supabase advisor scan (it only checks policy
existence, not runtime schema permissions) and was only caught by
actually impersonating a test user with `set role authenticated` +
`set request.jwt.claims`. Fixed in `0008`.

**RLS isolation verified behaviorally, not just structurally.**
Created two disposable test orgs/actors, impersonated each via JWT
claims, and confirmed: each actor sees exactly their own org, actor,
and farm records; neither can see the other's; neither can see
admin-only tables (`audit_logs`, `system_settings`); both can see
global reference data (`crops`) as intended. Test data was cleaned up
afterward â€” nothing persisted. Worth noting: org-level tables
(`organizations`, `projects`, `surveys`) resolve access through
`organization_members`, while actor-owned tables (`farms`,
`whatsapp_sessions`, etc.) resolve it through `actors.organization_id`
directly. **Both need to be populated when onboarding someone** â€” an
`actors` row alone isn't enough if they also need org-level visibility.

## Known issues still open

**1. Duplicate client-auth concept.** `api_clients` and `api_keys` both
exist, both organization-scoped, doing what looks like the same job.
Decide which one PulseID/PulseImpact actually use and drop the other.

**2. `FarmerPulse Demo` organization**, and **22 extra rows in `crops`**
beyond the 3 seeded this session, appeared without anyone in this
conversation adding them â€” confirms other active work on this project.
Decide if it's real pilot data or scratch, and reconcile before
partners start seeing it.

**3. Materialized view refresh.** `mv_dashboard_summary` is not
auto-refreshing â€” `app.refresh_dashboard()` / `app.refresh_all_dashboards()`
need to be called manually or wired to a scheduled job
(`scheduled_jobs` table exists for this but nothing populates it yet).

**4. The `.env` / `load_dotenv` timing bug on PulseID (PythonAnywhere)**
is still unresolved â€” outside the scope of anything touchable from
Supabase directly.

## Going forward

Once this is in git, treat the Supabase CLI as the source of truth
instead of ad-hoc `apply_migration` calls from whatever session happens
to be open:

```bash
supabase link --project-ref jmltamnqlqewwsqvcvme
supabase db pull          # sync any drift since this snapshot
supabase migration new <name>   # for every future change
supabase db push
```

That closes the gap that caused this snapshot to be necessary in the
first place â€” multiple disconnected sessions (human and AI) making live
schema changes with no shared history.


