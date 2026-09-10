const CACHE_NAME = 'titannova-fit-v4.0.0';
const ASSETS_TO_CACHE = [
  './',
  './index.html',
  './app.html',
  './planos.html',
  './manifest.json',
  './sw.js',
  './exercises_seed.js',
  './exercises_seed.json',
  './BUILD_GUIDE.md',
  'https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800;900&display=swap'
];

// Instalação do Service Worker e Caching dos Recursos Estáticos
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[ServiceWorker] Pré-cache de arquivos estáticos concluído.');
      return cache.addAll(ASSETS_TO_CACHE);
    })
  );
});

// Ativação e Limpeza Imediata de Caches Antigos
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            console.log('[ServiceWorker] Removendo cache antigo:', cache);
            return caches.delete(cache);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Intercepção de Requisições: Network-First para HTML/Navegação e Stale-While-Revalidate para Assets
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || !event.request.url.startsWith('http')) {
    return;
  }

  const isHtmlRequest = event.request.mode === 'navigate' || 
                        (event.request.headers.get('accept') && event.request.headers.get('accept').includes('text/html')) ||
                        event.request.url.endsWith('index.html') ||
                        event.request.url.endsWith('app.html') ||
                        event.request.url.endsWith('planos.html') ||
                        event.request.url.includes('/app') ||
                        event.request.url.includes('/planos') ||
                        event.request.url.endsWith('/');

  if (isHtmlRequest) {
    // Network-First para HTML: sempre busca a versão mais recente da rede, fallback para cache offline
    event.respondWith(
      fetch(event.request)
        .then((networkResponse) => {
          if (networkResponse && networkResponse.status === 200) {
            const responseClone = networkResponse.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, responseClone));
          }
          return networkResponse;
        })
        .catch(() => {
          console.log('[ServiceWorker] Offline - Servindo HTML do cache');
          const isAppPath = event.request.url.includes('/app') || event.request.url.includes('app.html');
          const targetFallback = isAppPath ? './app.html' : './index.html';
          return caches.match(targetFallback).then((cached) => cached || caches.match(event.request) || caches.match('./index.html'));
        })
    );
    return;
  }

  // Stale-While-Revalidate para outros recursos (fontes, scripts, imagens)
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request).then((networkResponse) => {
        if (networkResponse && (networkResponse.status === 200 || networkResponse.type === 'opaque' || networkResponse.type === 'cors')) {
          const responseToCache = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseToCache);
          });
        }
        return networkResponse;
      }).catch((err) => {
        console.log('[ServiceWorker] Offline - Servindo do cache local:', err);
      });

      return cachedResponse || fetchPromise;
    })
  );
});

// Manipulador de Notificações em Segundo Plano (Rest Timer)
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window' }).then((clientList) => {
      for (const client of clientList) {
        if (client.url === '/' && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow('./#active');
      }
    })
  );
});
