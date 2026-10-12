const { json } = require('../_lib/http');
const { validNativeHandoff, nativeSession } = require('../_lib/session');

module.exports = function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return json(res, 405, { error: 'Method not allowed.' });
  }
  const handoff = validNativeHandoff(req.body?.handoff);
  if (!handoff) return json(res, 401, { error: 'Sign-in handoff expired. Please sign in again.' });
  return json(res, 200, { session: nativeSession(handoff.email), expiresIn: 30 * 24 * 60 * 60 });
};
