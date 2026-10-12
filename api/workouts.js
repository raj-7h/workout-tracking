const { json } = require('./_lib/http');
const { validSession } = require('./_lib/session');
const { driveAccessToken } = require('./_lib/google');

const DRIVE = 'https://www.googleapis.com/drive/v3';
const UPLOAD = 'https://www.googleapis.com/upload/drive/v3';
const FILE_NAME = 'Repday-workout-data.json';
async function drive(url, token, options = {}) {
  const response = await fetch(url, { ...options, headers: { Authorization: `Bearer ${token}`, ...(options.headers || {}) } });
  if (!response.ok) {
    let message = `Drive returned ${response.status}`;
    try { message = (await response.json()).error?.message || message; } catch {}
    throw new Error(message);
  }
  return response;
}
async function getFile(token) {
  const q = encodeURIComponent(`name='${FILE_NAME}' and trashed=false`);
  const found = await drive(`${DRIVE}/files?q=${q}&spaces=drive&fields=files(id,name,modifiedTime)&pageSize=10`, token);
  const files = (await found.json()).files || [];
  if (!files.length) return { id: '', data: { days: {}, templates: {}, templateUpdatedAt: {}, updatedAt: 0 } };
  const response = await drive(`${DRIVE}/files/${encodeURIComponent(files[0].id)}?alt=media`, token);
  return { id: files[0].id, data: await response.json() };
}
async function writeFile(token, id, data) {
  const payload = JSON.stringify(data);
  if (id) {
    await drive(`${UPLOAD}/files/${encodeURIComponent(id)}?uploadType=media`, token, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: payload });
    return id;
  }
  const boundary = `repday_${require('node:crypto').randomUUID().replaceAll('-', '')}`;
  const metadata = JSON.stringify({ name: FILE_NAME, mimeType: 'application/json' });
  const body = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${payload}\r\n--${boundary}--`;
  const response = await drive(`${UPLOAD}/files?uploadType=multipart&fields=id`, token, { method: 'POST', headers: { 'Content-Type': `multipart/related; boundary=${boundary}` }, body });
  return (await response.json()).id;
}

function mergeData(existing, incoming) {
  const saved = { ...existing, ...incoming };
  const oldDays = existing.days && typeof existing.days === 'object' ? existing.days : {};
  const newDays = incoming.days && typeof incoming.days === 'object' ? incoming.days : {};
  const days = { ...oldDays };
  for (const [date, candidate] of Object.entries(newDays)) {
    const current = oldDays[date];
    if (!current || Number(candidate?.updatedAt || 0) >= Number(current.updatedAt || 0)) days[date] = candidate;
  }
  saved.days = days;

  const oldTemplates = existing.templates && typeof existing.templates === 'object' ? existing.templates : {};
  const newTemplates = incoming.templates && typeof incoming.templates === 'object' ? incoming.templates : {};
  const oldTimes = existing.templateUpdatedAt && typeof existing.templateUpdatedAt === 'object' ? existing.templateUpdatedAt : {};
  const newTimes = incoming.templateUpdatedAt && typeof incoming.templateUpdatedAt === 'object' ? incoming.templateUpdatedAt : {};
  const templates = { ...oldTemplates };
  const templateTimes = { ...oldTimes };
  for (const [weekday, candidate] of Object.entries(newTemplates)) {
    if (!(weekday in templates) || Number(newTimes[weekday] || 0) >= Number(oldTimes[weekday] || 0)) {
      templates[weekday] = candidate;
      if (weekday in newTimes) templateTimes[weekday] = newTimes[weekday];
    }
  }
  saved.templates = templates;
  saved.templateUpdatedAt = templateTimes;
  return saved;
}

module.exports = async function handler(req, res) {
  if (!validSession(req)) return json(res, 401, { error: 'Your app session expired. Sign in once more to resume automatic sync.' });
  try {
    const token = await driveAccessToken();
    if (req.method === 'GET') {
      const result = await getFile(token);
      return json(res, 200, result.data);
    }
    if (req.method === 'PUT') {
      const incoming = req.body;
      if (!incoming || typeof incoming.days !== 'object' || !incoming.days) return json(res, 400, { error: 'Invalid workout data.' });
      const existing = await getFile(token);
      const merged = mergeData(existing.data, incoming);
      await writeFile(token, existing.id, merged);
      return json(res, 200, { saved: true, data: merged });
    }
    res.setHeader('Allow', 'GET, PUT');
    return json(res, 405, { error: 'Method not allowed.' });
  } catch (error) { return json(res, 502, { error: error.message || 'Drive sync failed.' }); }
};
