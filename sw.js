const CACHE_NAME = 'titannova-fit-v4.1.0-secure';
const ASSETS_TO_CACHE = [
  './',
  './index.html',
  './app.html',
  './planos.html',
  './manifest.json',
  './exercises_seed.js',
  './exercises_seed.json',
  'https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800;900&display=swap'
];

// Instalação do Service Worker e Caching Resiliente dos Recursos Estáticos
self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      console.log('[ServiceWorker] Pré-caching resiliente de arquivos estáticos...');
      await Promise.allSettled(
        ASSETS_TO_CACHE.map(async (url) => {
          try {
            await cache.add(url);
          } catch (err) {
            console.warn('[ServiceWorker] Aviso não impeditivo ao cachear:', url, err);
          }
        })
      );
      console.log('[ServiceWorker] Instalação e pré-cache concluídos.');
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

// Intercepção de Requisições:
// 1. BYPASS TOTAL: APIs e endpoints autenticados (/api/*, *.supabase.co, headers Authorization/apikey)
// 2. Network-First para HTML/Navegação (garante app sempre atualizado, com fallback offline)
// 3. Stale-While-Revalidate estritamente para recursos estáticos públicos
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET' || !event.request.url.startsWith('http')) {
    return;
  }

  let url;
  try {
    url = new URL(event.request.url);
  } catch (_) {
    return;
  }

  // REGRA CRÍTICA DE SEGURANÇA:
  // Nunca armazenar em cache nem interceptar dados dinâmicos de usuários ou chamadas de API
  const isApiOrSupabase = url.pathname.startsWith('/api/') || 
                          url.hostname.includes('supabase.co') ||
                          event.request.headers.has('authorization') ||
                          event.request.headers.has('apikey');

  if (isApiOrSupabase) {
    // Pass-through direto pela rede
    return;
  }

  const isHtmlRequest = event.request.mode === 'navigate' || 
                        (event.request.headers.get('accept') && event.request.headers.get('accept').includes('text/html')) ||
                        url.pathname.endsWith('index.html') ||
                        url.pathname.endsWith('app.html') ||
                        url.pathname.endsWith('planos.html') ||
                        url.pathname === '/' ||
                        url.pathname.endsWith('/app') ||
                        url.pathname.endsWith('/planos');

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
          const isAppPath = url.pathname.includes('/app') || url.pathname.includes('app.html');
          const targetFallback = isAppPath ? './app.html' : './index.html';
          return caches.match(targetFallback).then((cached) => cached || caches.match(event.request) || caches.match('./index.html'));
        })
    );
    return;
  }

  // Stale-While-Revalidate estritamente para recursos estáticos públicos
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
