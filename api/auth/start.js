const crypto = require('node:crypto');
const { appUrl } = require('../_lib/http');
const { STATE_COOKIE, cookie } = require('../_lib/session');
const { env, redirectUri } = require('../_lib/google');
const { getRefreshToken } = require('../_lib/store');

module.exports = async function handler(req, res) {
  try {
    const isNative = req.query.native === '1';
    const state = `${isNative ? 'native.' : ''}${crypto.randomBytes(24).toString('base64url')}`;
    let hasRefreshToken = false;
    try { hasRefreshToken = !!(await getRefreshToken()); } catch {}
    const params = new URLSearchParams({ client_id: env('GOOGLE_CLIENT_ID'), redirect_uri: redirectUri(), response_type: 'code', scope: 'openid email https://www.googleapis.com/auth/drive.file', access_type: 'offline', include_granted_scopes: 'true', prompt: hasRefreshToken ? 'select_account' : 'consent', state });
    res.setHeader('Set-Cookie', cookie(STATE_COOKIE, state, 600));
    res.redirect(302, `https://accounts.google.com/o/oauth2/v2/auth?${params}`);
  } catch (error) { res.status(500).send(`${error.message} Return to ${appUrl()} after adding the missing settings.`); }
};
