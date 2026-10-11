# Repday workout tracker

Responsive workout tracker with weekday routines, per-set reps/weight/completion, exercise notes, video links, round exercise photos, progress chart, and personal-record scoring.

## Files

- `index.html` — app structure and Google Drive controls
- `styles.css` — responsive design
- `app.js` — workouts, charts, local cache, backup import/export
- `drive-sync.js` — Google Drive API authorization and syncing
- `manifest.webmanifest` and `service-worker.js` — installable app shell and offline page assets

Workout data saves locally first. After connecting Google Drive, the app syncs all workout data and compressed photos into `Repday-workout-data.json` in your Drive. It uses Google's `drive.file` permission, which limits app access to files it creates or that you explicitly open. The access token stays in memory; reconnect after reopening the app or when the token expires. The app also has **Export backup** and **Import backup** for manual JSON copies.

## Google Drive setup

1. Create a Google Cloud project and enable the Google Drive API.
2. Set up the OAuth consent screen / Google Auth Platform. For personal use while the app is in testing, add your own Google account as a test user.
3. Create an OAuth client ID with type **Web application**. Add the exact deployed HTTPS origin (for example, `https://your-name.pages.dev`) under **Authorized JavaScript origins**. This browser token flow does not need a client secret or redirect URI.
4. Publish the contents of this folder as a static site on Cloudflare Pages. The free plan is enough for this static app. Google sign-in will not work from a `file://` URL.
5. Open the HTTPS app on each device, paste the web client ID in the sync panel, click **Connect & sync**, and grant access. Do this on each device. Once connected, edits sync automatically after a short pause while the token is valid; use **Sync now** to reconcile after reopening.

First sync merges workout dates using each day's update timestamp. If two devices edit the same workout day while offline, the more recently saved version of that day wins. Avoid editing the same day offline on both devices at once.

Google accounts include up to 15 GB shared across Drive, Gmail, and Photos. Google Drive API usage under its current daily billing threshold does not incur extra charges; quotas and policies can change. The app is not connected to a Google account until you configure an OAuth client and authorize it.
