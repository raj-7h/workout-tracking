const crypto = require('node:crypto');

function config() {
  const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) throw new Error('Missing Supabase server environment settings.');
  return { url: SUPABASE_URL.replace(/\/$/, ''), key: SUPABASE_SERVICE_ROLE_KEY };
}
function encryptionKey() {
  if (!process.env.TOKEN_ENCRYPTION_KEY) throw new Error('Missing TOKEN_ENCRYPTION_KEY.');
  return crypto.createHash('sha256').update(process.env.TOKEN_ENCRYPTION_KEY).digest();
}
function encrypt(value) {
  const iv = crypto.randomBytes(12), cipher = crypto.createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), ciphertext].map((part) => part.toString('base64url')).join('.');
}
function decrypt(value) {
  const [iv, tag, ciphertext] = value.split('.').map((part) => Buffer.from(part, 'base64url'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', encryptionKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}
async function getRefreshToken() {
  const { url, key } = config();
  const response = await fetch(`${url}/rest/v1/repday_secrets?id=eq.1&select=refresh_token`, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
  if (!response.ok) throw new Error(`Token store read failed (${response.status}).`);
  const rows = await response.json();
  return rows[0]?.refresh_token ? decrypt(rows[0].refresh_token) : '';
}
async function saveRefreshToken(token) {
  const { url, key } = config();
  const response = await fetch(`${url}/rest/v1/repday_secrets?on_conflict=id`, {
    method: 'POST', headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify({ id: 1, refresh_token: encrypt(token), updated_at: new Date().toISOString() }),
  });
  if (!response.ok) throw new Error(`Token store write failed (${response.status}).`);
}

module.exports = { getRefreshToken, saveRefreshToken };
