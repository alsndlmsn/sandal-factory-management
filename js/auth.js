let session = null;
let profile = null;
async function initAuth() { if (!db) return; const result = await db.auth.getSession(); session = result.data.session; if (session) await loadProfile(); db.auth.onAuthStateChange(async (_event, next) => { session = next; if (session) await loadProfile(); render(); }); }
async function loadProfile() { if (!db || !session) return; const { data, error } = await db.from('profiles').select('id,email,full_name,is_enabled').eq('id', session.user.id).maybeSingle(); if (error) throw error; const roleResult = await db.from('user_roles').select('roles(code,name_ar)').eq('user_id', session.user.id).limit(1).maybeSingle(); profile = data || { id: session.user.id, email: session.user.email, full_name: session.user.email }; profile.role = roleResult.data?.roles?.code || 'manager'; profile.roleName = roleResult.data?.roles?.name_ar || 'المدير'; }
function isLoggedIn() { return Boolean(session); }
async function signIn(email,password) { if (!db) throw new Error('اتصال Supabase غير مكتمل. أضف المفتاح العام في js/config.js.'); const { data, error } = await db.auth.signInWithPassword({ email, password }); if (error) throw error; session = data.session; await loadProfile(); }
async function signOut() { if (db) await db.auth.signOut(); session = null; profile = null; }
function roleLabel() { return 'المدير'; }
