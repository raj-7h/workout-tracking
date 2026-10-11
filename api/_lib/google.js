const { getRefreshToken } = require('./store');

function env(name) { if (!process.env[name]) throw new Error(`Missing ${name} in Vercel environment variables.`); return process.env[name]; }
function redirectUri() { return `${env('APP_URL').replace(/\/$/, '')}/api/auth/callback`; }
async function exchangeCode(code) {
  const form = new URLSearchParams({ code, client_id: env('GOOGLE_CLIENT_ID'), client_secret: env('GOOGLE_CLIENT_SECRET'), redirect_uri: redirectUri(), grant_type: 'authorization_code' });
  const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_description || data.error || 'Google authorization failed.');
  return data;
}
async function verifyIdToken(idToken) {
  const response = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`);
  const data = await response.json();
  if (!response.ok || data.aud !== env('GOOGLE_CLIENT_ID') || data.email_verified !== 'true') throw new Error('Google could not verify this account.');
  const owner = env('OWNER_EMAIL').toLowerCase();
  if ((data.email || '').toLowerCase() !== owner) throw new Error('This workout app is configured for a different Google account.');
  return data.email;
}
async function driveAccessToken() {
  const refreshToken = await getRefreshToken();
  if (!refreshToken) throw new Error('Connect Google Drive once from this app first.');
  const form = new URLSearchParams({ client_id: env('GOOGLE_CLIENT_ID'), client_secret: env('GOOGLE_CLIENT_SECRET'), refresh_token: refreshToken, grant_type: 'refresh_token' });
  const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_description || data.error || 'Google token refresh failed.');
  return data.access_token;
}

module.exports = { env, redirectUri, exchangeCode, verifyIdToken, driveAccessToken };
