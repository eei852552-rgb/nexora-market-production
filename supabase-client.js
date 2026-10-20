(() => {
  const config = window.NEXORA_SUPABASE;
  const sessionKey = 'nexora.supabase.session';
  const base = `${config.url}`;

  function readSession() {
    try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; }
  }
  function saveSession(session) {
    if (session) localStorage.setItem(sessionKey, JSON.stringify(session));
    else localStorage.removeItem(sessionKey);
  }
  function authHeaders(session, extra = {}) {
    return { apikey: config.publishableKey, 'Content-Type': 'application/json', ...(session?.access_token ? { Authorization: `Bearer ${session.access_token}` } : {}), ...extra };
  }
  async function parse(response) {
    const text = await response.text();
    let body = null;
    try { body = text ? JSON.parse(text) : null; } catch { body = text; }
    if (!response.ok) {
      const message = body?.msg || body?.message || body?.error_description || body?.error || `Request failed (${response.status})`;
      const error = new Error(message);
      error.status = response.status;
      error.body = body;
      throw error;
    }
    return body;
  }
  async function refreshSession(session) {
    if (!session?.refresh_token) return null;
    const response = await fetch(`${base}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST', headers: authHeaders(null), body: JSON.stringify({ refresh_token: session.refresh_token })
    });
    if (!response.ok) { saveSession(null); return null; }
    const next = await response.json(); saveSession(next); return next;
  }
  async function session() {
    let current = readSession();
    if (!current) return null;
    if (current.expires_at && current.expires_at * 1000 < Date.now() + 30000) current = await refreshSession(current);
    return current;
  }
  async function authRequest(path, body, method = 'POST') {
    return parse(await fetch(`${base}/auth/v1/${path}`, { method, headers: authHeaders(null), body: body ? JSON.stringify(body) : undefined }));
  }
  async function signUp(email, password, displayName) {
    const result = await authRequest('signup', { email, password, data: { display_name: displayName } });
    if (result?.access_token) saveSession(result);
    return result;
  }
  async function signIn(email, password) {
    const result = await authRequest('token?grant_type=password', { email, password });
    saveSession(result); return result;
  }
  async function signOut() {
    const current = readSession();
    if (current?.access_token) { try { await fetch(`${base}/auth/v1/logout`, { method: 'POST', headers: authHeaders(current) }); } catch {} }
    saveSession(null);
  }
  async function user() {
    const current = await session();
    if (!current?.access_token) return null;
    try { return await parse(await fetch(`${base}/auth/v1/user`, { headers: authHeaders(current) })); }
    catch (error) { if (error.status === 401) { saveSession(null); return null; } throw error; }
  }
  async function rest(path, options = {}) {
    const current = await session();
    const response = await fetch(`${base}/rest/v1/${path}`, { ...options, headers: authHeaders(current, options.headers || {}) });
    return parse(response);
  }
  async function rpc(name, args = {}) {
    return rest(`rpc/${name}`, { method: 'POST', body: JSON.stringify(args) });
  }
  window.NexoraDB = { config, session, user, signUp, signIn, signOut, rest, rpc, saveSession };
})();
