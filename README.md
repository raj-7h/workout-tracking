# Setwise workout tracker

Setwise is a responsive workout tracker with weekday routines, per-set reps/weight/completion, exercise notes, video links, exercise photos, progress chart, and personal-record scoring. The existing Drive backup filename and local storage key stay as Repday so existing data is retained.

New workout days start with blank reps and weights; the most recent session's set values appear as comparison placeholders. Notes and video links stay in workout history, and the previous session's note is shown under the exercise note field. The first three sets have no remove control; added sets can be removed. Exercise photos can be replaced with **Change photo**.

## Automatic cross-device Drive sync

This version adds Vercel server-side API routes. Google OAuth refresh tokens are encrypted before being stored in a private Supabase table; the browser never receives the refresh token or Google client secret. Workout history stays in `Repday-workout-data.json` in Google Drive. An HttpOnly session cookie remembers each browser for up to one year. Sign in once on each new device; opening the Vercel URL reads the latest Drive data automatically, while uploads happen only after **Complete this day** is pressed.

The app reads and merges Drive data when it opens, then saves every edit locally on that device. It does **not** upload on each edit. Press **Complete this day** to upload the full merged workout history to Drive. If both devices edit the same workout day offline, the later saved version wins.

## Setup checklist

You will create a Supabase project, add its private settings to Vercel, update the Google OAuth client, and redeploy. No secrets belong in this folder or in chat.

### 1. Deploy this folder to Vercel

Deploy the **contents** of `repday-source` as the Vercel project root. Keep the `api/` folder beside `index.html`; Vercel detects its serverless functions automatically. The current deployment domain is `workout-tracking-ebon.vercel.app`. The Hobby plan can host personal, non-commercial projects; see [Vercel Hobby](https://vercel.com/docs/plans/hobby).

### 2. Create the private token table in Supabase

1. Create a Supabase project on its Free plan.
2. Open **SQL Editor** and run [`supabase-setup.sql`](./supabase-setup.sql).
3. In Supabase **Project Settings → API Keys**, copy the project URL and create a new **Secret key** for this backend. Put it only in Vercel environment variables, never in browser JavaScript. Keep the table without public RLS policies. Supabase Free includes a small database suitable for the single encrypted token row; free projects may pause after seven days with no activity, so an actively used app should avoid that inactivity pause. See [Supabase pricing](https://supabase.com/pricing).

### 3. Update your Google OAuth client

In the Google Cloud project that already has Drive API enabled:

1. Keep the OAuth app audience **External** and add your Google account as a test user if it is still in Testing.
2. Open **Google Auth Platform → Clients** and edit the Web application client.
3. Add this **Authorized JavaScript origin**: `https://workout-tracking-ebon.vercel.app`.
4. Add this **Authorized redirect URI**: `https://workout-tracking-ebon.vercel.app/api/auth/callback`.
5. Copy the client ID and client secret. Store both only in Vercel environment variables.

Google says refresh tokens issued while an External OAuth app is in **Testing** expire after seven days for Drive scopes. To avoid a weekly reconnect, set the app to **In production** in Google Auth Platform. Google may require verification for sensitive scopes before broader distribution; an unverified app can show a warning and has a user cap. For this personal single-user app, follow the status and verification instructions Google shows for your project. See [Google testing-mode rules](https://support.google.com/cloud/answer/15549945?hl=en) and [OAuth verification](https://support.google.com/cloud/answer/13463073?hl=en).

### 4. Add Vercel environment variables

In **Vercel → Project → Settings → Environment Variables**, add these for **Production**:

| Name | Value |
| --- | --- |
| `APP_URL` | `https://workout-tracking-ebon.vercel.app` |
| `GOOGLE_CLIENT_ID` | Your Google OAuth Web client ID |
| `GOOGLE_CLIENT_SECRET` | Its client secret |
| `OWNER_EMAIL` | The one Google account allowed to use this app |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SECRET_KEY` | A new Supabase Secret key for this backend |
| `SESSION_SECRET` | A new random secret, at least 32 random characters |
| `TOKEN_ENCRYPTION_KEY` | A separate new random secret, at least 32 random characters |

Generate the last two secrets with a password manager or a local secure random generator. Do not reuse the Google client secret. After saving variables, **redeploy** the Vercel project so the functions receive them.

### 5. Connect once on each device

1. Open `https://workout-tracking-ebon.vercel.app` on your laptop and press **Enable Drive sync** once.
2. Sign in with the `OWNER_EMAIL` account and approve the requested Drive access. This initial approval stores an encrypted refresh token in Supabase.
3. Open `https://workout-tracking-ebon.vercel.app` on your iPhone and press **Enable Drive sync** once to establish that browser's remembered session. The app hides the connection panel while the session is active. On later visits, it reads Drive automatically; press **Complete this day** when you want to upload workout changes.
4. Add the app to your iPhone Home Screen if you want an app-like icon. Use the HTTPS Vercel URL, not the local `file://` preview.

Each browser/device needs a first sign-in because its secure session cookie is device-specific. Subsequent visits on that device automatically restore the Drive session. Clearing website data or revoking Google access requires signing in again.

### Refresh the iPhone app

After pushing changes, wait for the Vercel Production deployment to finish. Open the Vercel URL in Safari and refresh the page; the service-worker cache version is changed so the updated files replace the old interface. If the Home Screen still shows the old icon, first press **Complete this day** for unsynced workouts or export a backup, then remove the old Home Screen shortcut and add it again from Safari using **Share → Add to Home Screen**.

## Security and limits

- Vercel stores secrets as encrypted environment variables. The Google client secret and Drive refresh token are never shipped to the browser.
- Supabase's Secret key bypasses row-level security, so it must only exist in Vercel server-side settings. The refresh token is additionally encrypted with `TOKEN_ENCRYPTION_KEY` before it is stored.
- If a Supabase legacy `service_role` key was exposed, replace it with the new Secret key in Vercel, redeploy, and then disable the exposed legacy key in Supabase **Project Settings → API Keys**.
- Keep the Supabase project and Vercel project private to your own accounts. `OWNER_EMAIL` limits successful app sessions to one Google account.
- Google authorization can still be revoked by the account owner. If that happens, reconnect once. The app shows the connection panel again if automatic sync stops.
- Local backups remain available through **Export backup** and **Import backup**.

## Files

- `index.html`, `styles.css`, `app.js` — responsive workout app and local cache
- `drive-sync.js` — auto-sync client, session check, and local/Drive merge
- `api/` — Vercel OAuth callback, remembered session, encrypted token storage, and Drive proxy
- `ios/Setwise/` — SwiftUI iPhone app, Google sign-in handoff, Keychain session, workout sync, and HealthKit export
- `supabase-setup.sql` — private one-row token table
- `manifest.webmanifest`, `service-worker.js` — installable offline app shell
- `icon.svg`, `icon-180.png`, `icon-512.png` — clear barbell app icons for browser and iPhone Home Screen

## Apple Health

The web app cannot directly access Apple Health. A native iOS companion is now in [`ios/Setwise`](./ios/Setwise). It uses the same workout API and Google account, keeps an offline draft on the iPhone until **Complete this day**, then saves the workout to Google Drive and writes a Traditional Strength Training workout to Apple Health. Use **Start workout** for a meaningful duration. Setwise keeps detailed exercises, reps, weights, notes, photos, links, records, and charts; Health stores a workout summary with Setwise metadata. No calories or heart-rate values are invented.

### Build the iPhone app

1. Push this repository to GitHub and wait for the Vercel Production deployment. The native sign-in handoff adds `POST /api/auth/native-session`; the iPhone app needs that route deployed before Google sign-in can finish.
2. Open [`ios/Setwise/Setwise.xcodeproj`](./ios/Setwise/Setwise.xcodeproj) in Xcode.
3. In **Signing & Capabilities**, select your Apple Account’s team and check that Xcode accepts the HealthKit capability. Connect your iPhone to the Mac, select it as the run destination, and press **Run**.
4. In Setwise, choose **Continue with Google** and sign in with the Google account already connected to Drive. The iOS app stores its app session in the iPhone Keychain.
5. Tap **Start workout** when training begins. After **Complete this day**, Setwise uploads your merged workout history and requests permission to add the workout to Apple Health. You can manage that permission later in iPhone Settings or Health.

Apple allows building and testing on personal devices with Xcode without program membership, but HealthKit capability availability depends on the Apple team/signing profile. Apple lists HealthKit as a developer capability and says the paid Apple Developer Program costs USD $99 per year. Check the HealthKit capability in Xcode before paying; no membership or purchase is included here. If your free Personal Team cannot sign the HealthKit entitlement, the no-cost option remains the existing Add-to-Home-Screen web app without Health sync. See [Apple’s capability availability](https://developer.apple.com/help/account/reference/supported-capabilities-ios), [membership details and pricing](https://developer.apple.com/programs/whats-included/), and [HealthKit setup](https://developer.apple.com/documentation/healthkit/setting-up-healthkit).

The simulator can compile this app, but HealthKit data sync must be tried on a real iPhone. The Health app does not provide a standard per-set lifting log, so detailed tracking remains in Setwise.
