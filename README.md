# Repday workout tracker

Repday is a responsive workout tracker with weekday routines, per-set reps/weight/completion, exercise notes, video links, exercise photos, progress chart, and personal-record scoring.

## Automatic cross-device Drive sync

This version adds Vercel server-side API routes. Google OAuth refresh tokens are encrypted before being stored in a private Supabase table; the browser never receives the refresh token or Google client secret. Workout history stays in `Repday-workout-data.json` in Google Drive. An HttpOnly session cookie remembers each browser for up to one year. Sign in once on each new device; after that, opening the Vercel URL syncs automatically.

The app reads and merges Drive data when it opens, then saves every edit locally on that device. It does **not** upload on each edit. Press **Complete this day** to upload the full merged workout history to Drive. If both devices edit the same workout day offline, the later saved version wins.

## Setup checklist

You will create a Supabase project, add its private settings to Vercel, update the Google OAuth client, and redeploy. No secrets belong in this folder or in chat.

### 1. Deploy this folder to Vercel

Deploy the **contents** of `repday-source` as the Vercel project root. Keep the `api/` folder beside `index.html`; Vercel detects its serverless functions automatically. Use the same project and domain that serves your current `workout-tracking-sandy.vercel.app` URL. The Hobby plan can host personal, non-commercial projects; see [Vercel Hobby](https://vercel.com/docs/plans/hobby).

### 2. Create the private token table in Supabase

1. Create a Supabase project on its Free plan.
2. Open **SQL Editor** and run [`supabase-setup.sql`](./supabase-setup.sql).
3. In Supabase project settings, copy the project URL and the **service_role** key. Put them only in Vercel environment variables, never in browser JavaScript. Keep the table without public RLS policies. Supabase Free includes a small database suitable for the single encrypted token row; free projects may pause after seven days with no activity, so an actively used app should avoid that inactivity pause. See [Supabase pricing](https://supabase.com/pricing).

### 3. Update your Google OAuth client

In the Google Cloud project that already has Drive API enabled:

1. Keep the OAuth app audience **External** and add your Google account as a test user if it is still in Testing.
2. Open **Google Auth Platform → Clients** and edit the Web application client.
3. Keep this **Authorized JavaScript origin**: `https://workout-tracking-sandy.vercel.app`.
4. Add this **Authorized redirect URI**: `https://workout-tracking-sandy.vercel.app/api/auth/callback`.
5. Copy the client ID and client secret. Store both only in Vercel environment variables.

Google says refresh tokens issued while an External OAuth app is in **Testing** expire after seven days for Drive scopes. To avoid a weekly reconnect, set the app to **In production** in Google Auth Platform. Google may require verification for sensitive scopes before broader distribution; an unverified app can show a warning and has a user cap. For this personal single-user app, follow the status and verification instructions Google shows for your project. See [Google testing-mode rules](https://support.google.com/cloud/answer/15549945?hl=en) and [OAuth verification](https://support.google.com/cloud/answer/13463073?hl=en).

### 4. Add Vercel environment variables

In **Vercel → Project → Settings → Environment Variables**, add these for **Production**:

| Name | Value |
| --- | --- |
| `APP_URL` | `https://workout-tracking-sandy.vercel.app` |
| `GOOGLE_CLIENT_ID` | Your Google OAuth Web client ID |
| `GOOGLE_CLIENT_SECRET` | Its client secret |
| `OWNER_EMAIL` | The one Google account allowed to use this app |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | The Supabase `service_role` key |
| `SESSION_SECRET` | A new random secret, at least 32 random characters |
| `TOKEN_ENCRYPTION_KEY` | A separate new random secret, at least 32 random characters |

Generate the last two secrets with a password manager or a local secure random generator. Do not reuse the Google client secret. After saving variables, **redeploy** the Vercel project so the functions receive them.

### 5. Connect once on each device

1. Open `https://workout-tracking-sandy.vercel.app` on your laptop and press **Enable Drive sync** once.
2. Sign in with the `OWNER_EMAIL` account and approve the requested Drive access. This initial approval stores an encrypted refresh token in Supabase.
3. Open the same HTTPS URL on your iPhone and press **Enable Drive sync** once to establish that browser's remembered session. The app hides the connection panel while the session is active. On later visits, it reads Drive automatically; press **Complete this day** when you want to upload workout changes.
4. Add the app to your iPhone Home Screen if you want an app-like icon. Use the HTTPS Vercel URL, not the local `file://` preview.

Each browser/device needs a first sign-in because its secure session cookie is device-specific. Subsequent visits on that device automatically restore the Drive session. Clearing website data or revoking Google access requires signing in again.

## Security and limits

- Vercel stores secrets as encrypted environment variables. The Google client secret and Drive refresh token are never shipped to the browser.
- Supabase's `service_role` key bypasses row-level security, so it must only exist in Vercel server-side settings. The refresh token is additionally encrypted with `TOKEN_ENCRYPTION_KEY` before it is stored.
- Keep the Supabase project and Vercel project private to your own accounts. `OWNER_EMAIL` limits successful app sessions to one Google account.
- Google authorization can still be revoked by the account owner. If that happens, reconnect once. The app shows the connection panel again if automatic sync stops.
- Local backups remain available through **Export backup** and **Import backup**.

## Files

- `index.html`, `styles.css`, `app.js` — responsive workout app and local cache
- `drive-sync.js` — auto-sync client, session check, and local/Drive merge
- `api/` — Vercel OAuth callback, remembered session, encrypted token storage, and Drive proxy
- `supabase-setup.sql` — private one-row token table
- `manifest.webmanifest`, `service-worker.js` — installable offline app shell
