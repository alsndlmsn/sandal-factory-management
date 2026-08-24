import { getSession, getProfile, isForcedPasswordChange } from './auth.js';

const publicRoutes = new Set(['login', 'change-password']);
let routeHandler = () => {};

export function currentRoute() {
  const raw = window.location.hash.replace(/^#\/?/, '').split('?')[0].trim();
  return raw || 'dashboard';
}

export function navigate(route) {
  const target = String(route || 'dashboard').replace(/^#\/?/, '').replace(/^\//, '');
  window.location.hash = `#/${target}`;
}

export function startRouter(handler) {
  routeHandler = handler;
  window.addEventListener('hashchange', renderRoute);
  renderRoute();
}

export function allowed(route) {
  const session = getSession();
  const profile = getProfile();
  if (!session && !publicRoutes.has(route)) return false;
  if (session && isForcedPasswordChange() && route !== 'change-password') return false;
  if (session && route === 'login') return false;
  if (!profile && session && route !== 'change-password') return false;
  return true;
}

function renderRoute() {
  let route = currentRoute();
  if (!allowed(route)) {
    route = getSession() ? (isForcedPasswordChange() ? 'change-password' : 'dashboard') : 'login';
    if (currentRoute() !== route) window.location.hash = `#/${route}`;
  }
  routeHandler(route);
}
