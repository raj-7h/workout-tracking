const { json, appUrl } = require('../_lib/http');
const { STATE_COOKIE, readCookie, cookie, sessionCookie } = require('../_lib/session');
const { exchangeCode, verifyIdToken } = require('../_lib/google');
const { getRefreshToken, saveRefreshToken } = require('../_lib/store');

module.exports = async function handler(req, res) {
  try {
    if (req.query.error) return res.redirect(302, `${appUrl()}/?auth=cancelled`);
    const state = readCookie(req, STATE_COOKIE);
    if (!state || state !== req.query.state) return json(res, 400, { error: 'Google sign-in expired or could not be verified. Please try again.' });
    res.setHeader('Set-Cookie', cookie(STATE_COOKIE, '', 0));
    const token = await exchangeCode(req.query.code || '');
    const email = await verifyIdToken(token.id_token || '');
    if (token.refresh_token) await saveRefreshToken(token.refresh_token);
    else if (!(await getRefreshToken())) throw new Error('Google did not provide a long-term token. Revoke Repday in your Google Account security settings, then connect again.');
    res.setHeader('Set-Cookie', [cookie(STATE_COOKIE, '', 0), sessionCookie(email)]);
    res.redirect(302, `${appUrl()}/?connected=1`);
  } catch (error) { res.status(400).send(`Google setup failed: ${error.message}`); }
};
