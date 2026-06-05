const CACHE = 'wheresmyv3';
const SHELL = [
  './',
  './index.html',
  './manifest.json',
  './icon.svg',
  './favicon.ico',
  './favicon.png',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Only the app shell is cached (same-origin GET). Supabase auth + data
// calls (cross-origin / non-GET) always go straight to the network and are
// never stored, so signed-out reloads can't serve cached private data.
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  const isShell = e.request.method === 'GET' && url.origin === self.location.origin;

  if (!isShell) {
    e.respondWith(fetch(e.request));
    return;
  }

  // Network-first for the shell, fall back to cache when offline.
  e.respondWith(
    fetch(e.request)
      .then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
