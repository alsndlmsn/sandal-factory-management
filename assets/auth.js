import { requireSupabase, supabase, getErrorMessage } from './supabase-client.js';

let currentSession = null;
let currentProfile = null;
const listeners = new Set();

function notify() {
  listeners.forEach((listener) => listener({ session: currentSession, profile: currentProfile }));
}

export function subscribeAuth(listener) {
  listeners.add(listener);
  listener({ session: currentSession, profile: currentProfile });
  return () => listeners.delete(listener);
}

export async function restoreSession() {
  if (!supabase) return { session: null, profile: null };
  const { data, error } = await supabase.auth.getSession();
  if (error) throw error;
  currentSession = data.session;
  if (currentSession) await loadProfile();
  notify();
  return { session: currentSession, profile: currentProfile };
}

export async function loadProfile() {
  if (!supabase || !currentSession?.user?.id) return null;
  const { data, error } = await supabase.from('profiles').select('*').eq('id', currentSession.user.id).maybeSingle();
  if (error) throw error;
  currentProfile = data;
  notify();
  return currentProfile;
}

export async function signIn(email, password) {
  const client = requireSupabase();
  const { data, error } = await client.auth.signInWithPassword({ email: email.trim(), password });
  if (error) throw new Error(getErrorMessage(error));
  currentSession = data.session;
  await loadProfile();
  return { session: currentSession, profile: currentProfile };
}

export async function signOut() {
  if (!supabase) return;
  const { error } = await supabase.auth.signOut();
  if (error) throw new Error(getErrorMessage(error));
  currentSession = null;
  currentProfile = null;
  notify();
}

export async function changeOwnPassword(password) {
  const client = requireSupabase();
  const { error } = await client.auth.updateUser({ password });
  if (error) throw new Error(getErrorMessage(error));
  const { error: rpcError } = await client.rpc('complete_password_change');
  if (rpcError) throw new Error(getErrorMessage(rpcError));
  await loadProfile();
}

export function getSession() { return currentSession; }
export function getProfile() { return currentProfile; }
export function getRole() { return currentProfile?.role || null; }
export function isForcedPasswordChange() { return Boolean(currentProfile?.must_change_password); }

if (supabase) {
  supabase.auth.onAuthStateChange(async (_event, session) => {
    currentSession = session;
    if (session) {
      try { await loadProfile(); } catch (error) { console.error(error); }
    } else {
      currentProfile = null;
    }
    notify();
  });
}
