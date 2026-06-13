/* ── Techychat Service Worker ─────────────────────────────── */
const CACHE  = 'techychat-v2';
const SHELL  = [
  '/',
  '/auth.html',
  '/messages.html',
  '/chat.html',
  '/posts.html',
  '/friends.html',
  '/notifications.html',
  '/profile.html',
  '/user-profile.html',
  '/contact.html',
  '/css/main.css',
  '/js/app.js',
  '/manifest.json',
  '/assets/icon-192.png',
  '/assets/icon-512.png',
  '/assets/icon.svg',
];

/* Install – pre-cache shell */
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

/* Activate – purge old caches */
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

/* Fetch – network-first for API, cache-first for shell */
self.addEventListener('fetch', e => {
  const { request } = e;
  const url = new URL(request.url);

  // Always network for Supabase API requests
  if (url.hostname.includes('supabase.co')) return;

  // Network-first for navigations
  if (request.mode === 'navigate') {
    e.respondWith(
      fetch(request)
        .catch(() => caches.match('/auth.html'))
    );
    return;
  }

  // Cache-first for static assets
  e.respondWith(
    caches.match(request).then(cached => {
      if (cached) return cached;
      return fetch(request).then(res => {
        if (res && res.status === 200 && res.type !== 'opaque') {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(request, clone));
        }
        return res;
      });
    })
  );
});
