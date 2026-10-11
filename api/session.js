const { json } = require('./_lib/http');
const { validSession } = require('./_lib/session');

module.exports = function handler(req, res) {
  const session = validSession(req);
  if (!session) return json(res, 401, { connected: false });
  return json(res, 200, { connected: true, email: session.email });
};
