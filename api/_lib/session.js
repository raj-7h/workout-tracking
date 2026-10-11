const crypto = require('node:crypto');

const COOKIE = 'repday_session';
const STATE_COOKIE = 'repday_oauth_state';
const b64 = (value) => Buffer.from(value).toString('base64url');
function signature(value) { return crypto.createHmac('sha256', process.env.SESSION_SECRET || '').update(value).digest('base64url'); }
function makeSession(email) {
  const payload = b64(JSON.stringify({ email, exp: Date.now() + 365 * 24 * 60 * 60 * 1000 }));
  return `${payload}.${signature(payload)}`;
}
function readCookie(req, name) {
  const part = (req.headers.cookie || '').split(';').map((item) => item.trim()).find((item) => item.startsWith(`${name}=`));
  return part ? decodeURIComponent(part.slice(name.length + 1)) : '';
}
function validSession(req) {
  const value = readCookie(req, COOKIE), [payload, supplied] = value.split('.');
  if (!payload || !supplied || !process.env.SESSION_SECRET) return null;
  const expected = signature(payload);
  const a = Buffer.from(supplied), b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString());
    return data.exp > Date.now() && data.email.toLowerCase() === (process.env.OWNER_EMAIL || '').toLowerCase() ? data : null;
  } catch { return null; }
}
function cookie(name, value, maxAge) {
  return `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAge}`;
}
function sessionCookie(email) { return cookie(COOKIE, makeSession(email), 365 * 24 * 60 * 60); }

module.exports = { COOKIE, STATE_COOKIE, readCookie, validSession, cookie, sessionCookie };
