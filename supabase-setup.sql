-- Run once in the Supabase SQL Editor. The backend uses the service role key;
-- browser/anonymous clients must not be able to read this refresh token.
create table if not exists public.repday_secrets (
  id integer primary key check (id = 1),
  refresh_token text not null,
  updated_at timestamptz not null default now()
);

alter table public.repday_secrets enable row level security;
revoke all on table public.repday_secrets from anon, authenticated;

-- Do not add public policies to this table. Only the server-side service role
-- configured in Vercel should access it.
