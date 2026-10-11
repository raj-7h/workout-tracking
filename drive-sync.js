(() => {
  const DRIVE_API = 'https://www.googleapis.com/drive/v3';
  const UPLOAD_API = 'https://www.googleapis.com/upload/drive/v3';
  const SCOPE = 'https://www.googleapis.com/auth/drive.file';
  const FILE_NAME = 'Repday-workout-data.json';
  let accessToken = '', expiresAt = 0, fileId = '', timer = 0, running = false, pending = null;
  const $ = (selector) => document.querySelector(selector);
  const status = (message) => { if ($('#driveStatus')) $('#driveStatus').textContent = message; };
  const tokenIsValid = () => !!accessToken && Date.now() < expiresAt - 30000;
  const errorMessage = async (response) => { try { const body = await response.json(); return body.error?.message || `Drive returned ${response.status}`; } catch { return `Drive returned ${response.status}`; } };

  async function api(url, options = {}) {
    if (!tokenIsValid()) throw new Error('Reconnect Drive to continue syncing. Your local data is saved.');
    const response = await fetch(url, { ...options, headers: { Authorization: `Bearer ${accessToken}`, ...(options.headers || {}) } });
    if (!response.ok) { if (response.status === 401) { accessToken = ''; } throw new Error(await errorMessage(response)); }
    return response;
  }
  async function findBackup() {
    const query = encodeURIComponent(`name='${FILE_NAME}' and trashed=false`);
    const response = await api(`${DRIVE_API}/files?q=${query}&spaces=drive&fields=files(id,name,modifiedTime)&pageSize=10`);
    const result = await response.json(); return result.files?.[0] || null;
  }
  async function readBackup(id) {
    const response = await api(`${DRIVE_API}/files/${encodeURIComponent(id)}?alt=media`);
    return response.json();
  }
  async function writeBackup(data, id) {
    const payload = JSON.stringify(data);
    if (id) {
      await api(`${UPLOAD_API}/files/${encodeURIComponent(id)}?uploadType=media`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: payload });
      return id;
    }
    const boundary = `repday_${crypto.randomUUID().replaceAll('-', '')}`;
    const metadata = JSON.stringify({ name: FILE_NAME, mimeType: 'application/json' });
    const body = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${payload}\r\n--${boundary}--`;
    const response = await api(`${UPLOAD_API}/files?uploadType=multipart&fields=id,name`, { method: 'POST', headers: { 'Content-Type': `multipart/related; boundary=${boundary}` }, body });
    return (await response.json()).id;
  }
  function mergeData(local, remote) {
    const merged = { days: {}, templates: {}, templateUpdatedAt: {}, updatedAt: Math.max(local.updatedAt || 0, remote.updatedAt || 0) };
    for (const date of new Set([...Object.keys(local.days || {}), ...Object.keys(remote.days || {})])) {
      const a = local.days?.[date], b = remote.days?.[date];
      merged.days[date] = !a ? b : !b ? a : (Number(b.updatedAt) || 0) > (Number(a.updatedAt) || 0) ? b : a;
    }
    for (const weekday of new Set([...Object.keys(local.templates || {}), ...Object.keys(remote.templates || {})])) {
      const a = local.templates?.[weekday], b = remote.templates?.[weekday];
      const timeA = Number(local.templateUpdatedAt?.[weekday]) || 0, timeB = Number(remote.templateUpdatedAt?.[weekday]) || 0;
      merged.templates[weekday] = !a ? b : !b ? a : timeB > timeA ? b : a;
      merged.templateUpdatedAt[weekday] = Math.max(timeA, timeB);
    }
    return merged;
  }
  function notifyData(data) { window.dispatchEvent(new CustomEvent('repday:data-loaded', { detail: data })); }
  async function synchronize(data) {
    const existing = await findBackup(); fileId = existing?.id || '';
    let merged = data;
    if (existing) merged = mergeData(data, await readBackup(existing.id));
    localStorage.setItem('repday-v1', JSON.stringify(merged)); notifyData(merged);
    if (!existing || JSON.stringify(merged) !== JSON.stringify(await readBackup(existing.id))) fileId = await writeBackup(merged, fileId);
    status(`Synced with Google Drive · ${new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`);
  }
  async function flush() {
    if (running || !pending || !tokenIsValid()) return;
    running = true; const snapshot = pending; pending = null;
    try { await synchronize(snapshot); }
    catch (error) { status(`Local save kept. Drive sync needs attention: ${error.message}`); }
    finally { running = false; if (pending && tokenIsValid()) { clearTimeout(timer); timer = setTimeout(flush, 500); } }
  }
  function queue(data) {
    pending = JSON.parse(JSON.stringify(data));
    if (!tokenIsValid()) return;
    status('Saved here · syncing to Drive…'); clearTimeout(timer); timer = setTimeout(flush, 1100);
  }
  function requestToken(clientId) {
    return new Promise((resolve, reject) => {
      const tokenClient = google.accounts.oauth2.initTokenClient({
        client_id: clientId, scope: SCOPE,
        callback: (response) => {
          if (response.error || !response.access_token) return reject(new Error(response.error_description || response.error || 'Google did not return an access token.'));
          accessToken = response.access_token; expiresAt = Date.now() + (Number(response.expires_in) || 3600) * 1000; resolve();
        },
      });
      tokenClient.requestAccessToken();
    });
  }
  async function connect() {
    const input = $('#driveClientId'), clientId = input.value.trim();
    if (location.protocol === 'file:') return status('Host the app on HTTPS first; Google sign-in will not work from a file:// page.');
    if (!clientId) { status('Paste your Google OAuth web client ID first.'); input.focus(); return; }
    localStorage.setItem('repday-drive-client-id', clientId);
    if (!window.google?.accounts?.oauth2) return status('Google sign-in did not load. Check your internet connection and try again.');
    status('Waiting for Google authorization…');
    try { await requestToken(clientId); await synchronize(JSON.parse(localStorage.getItem('repday-v1') || '{"days":{},"templates":{}}')); $('#driveSync').hidden = false; }
    catch (error) { status(`Drive connection failed: ${error.message}`); }
  }
  async function syncNow() {
    if (!tokenIsValid()) return status('Reconnect Drive first. Your latest changes remain saved on this device.');
    clearTimeout(timer); pending = null;
    try { await synchronize(JSON.parse(localStorage.getItem('repday-v1') || '{"days":{},"templates":{}}')); }
    catch (error) { status(`Local save kept. Drive sync needs attention: ${error.message}`); }
  }
  function init() {
    const input = $('#driveClientId'); input.value = localStorage.getItem('repday-drive-client-id') || '';
    input.onchange = () => localStorage.setItem('repday-drive-client-id', input.value.trim());
    $('#driveConnect').onclick = connect; $('#driveSync').onclick = syncNow;
  }
  window.RepdayDrive = { queue, connect, syncNow };
  document.addEventListener('DOMContentLoaded', init);
})();
