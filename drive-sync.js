(() => {
  let connected = false;
  const $ = (selector) => document.querySelector(selector);
  const status = (message) => { if ($('#driveStatus')) $('#driveStatus').textContent = message; };
  async function request(url, options = {}) {
    const response = await fetch(url, { ...options, credentials: 'same-origin', cache: 'no-store', headers: { ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...(options.headers || {}) } });
    let data = {};
    try { data = await response.json(); } catch {}
    if (!response.ok) throw new Error(url === '/api/session' && response.status === 401 ? 'not connected' : (data.error || `Server returned ${response.status}`));
    return data;
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
  function markConnected() {
    connected = true;
    $('#driveCard').hidden = true;
  }
  async function synchronize(data) {
    const remote = await request('/api/workouts');
    const merged = mergeData(data, remote);
    localStorage.setItem('repday-v1', JSON.stringify(merged));
    await request('/api/workouts', { method: 'PUT', body: JSON.stringify(merged) });
    if (JSON.stringify(merged) !== JSON.stringify(data)) notifyData(merged);
    markConnected();
    status(`Saved to Google Drive · ${new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`);
  }
  function queue() {
    if (!connected) return;
    status('Saved on this device · complete the day to update Drive.');
  }
  async function connect() {
    if (location.protocol === 'file:') return status('Open the deployed HTTPS Vercel URL to enable automatic sync.');
    status('Opening Google sign-in…'); location.assign('/api/auth/start');
  }
  async function syncNow() {
    if (!connected) return connect();
    try {
      await synchronize(JSON.parse(localStorage.getItem('repday-v1') || '{"days":{},"templates":{}}'));
      return true;
    } catch (error) {
      connected = false; $('#driveCard').hidden = false;
      status(`Saved on this device. Drive update failed: ${error.message}`);
      return false;
    }
  }
  async function initialize() {
    if (location.protocol === 'file:') { status('Automatic sync works on your deployed HTTPS Vercel URL.'); return; }
    const params = new URLSearchParams(location.search);
    if (params.has('connected')) history.replaceState({}, '', location.pathname);
    try {
      const session = await request('/api/session');
      if (!session.connected) throw new Error('not connected');
      connected = true;
      const remote = await request('/api/workouts');
      const local = JSON.parse(localStorage.getItem('repday-v1') || '{"days":{},"templates":{}}');
      const merged = mergeData(local, remote);
      localStorage.setItem('repday-v1', JSON.stringify(merged));
      if (JSON.stringify(merged) !== JSON.stringify(local)) notifyData(merged);
      markConnected();
      status('Drive data loaded · complete a day to upload your changes.');
    } catch (error) {
      connected = false; $('#driveCard').hidden = false;
      if (params.has('auth')) status('Google sign-in was cancelled. Your workouts remain saved on this device.');
      else if (error.message !== 'not connected') status(`Automatic sync needs attention: ${error.message}`);
      else status('Sign in once on this device to enable automatic Drive sync.');
    }
  }
  $('#driveConnect').onclick = connect;
  window.RepdayDrive = { queue, connect, syncNow, ready: initialize() };
})();
