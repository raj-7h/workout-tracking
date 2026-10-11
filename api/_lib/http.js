function json(res, status, body) {
  res.status(status).setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(body));
}

function appUrl() {
  const value = process.env.APP_URL;
  if (!value || !value.startsWith('https://')) throw new Error('APP_URL must be your deployed HTTPS Vercel URL.');
  return value.replace(/\/$/, '');
}

module.exports = { json, appUrl };
