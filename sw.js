const CACHE_NAME = 'sandal-factory-static-v28';
const APP_SHELL = ['./', './index.html', './favicon.svg', './css/main.css?v=26', './js/config.js?v=19', './js/supabase.js?v=19', './js/app.js?v=26', './js/guidance.js?v=1', './js/printing.js?v=3', './manifest.json'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE_NAME).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  event.respondWith(fetch(request).then(response => {
    const copy = response.clone();
    caches.open(CACHE_NAME).then(cache => cache.put(request, copy));
    return response;
  }).catch(() => caches.match(request).then(cached => cached || caches.match('./index.html'))));
});
