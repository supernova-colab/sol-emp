// Guarda la app para que abra rápido y sin internet; siempre intenta traer la versión nueva primero.
// Solo maneja archivos de la propia app: la base de datos y las librerías externas van directo a internet.
const CACHE="sol-emp-v19";
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(["./","./index.html","./manifest.webmanifest","./icon-192.png","./monigote.png"].map(u=>new Request(u,{cache:"reload"})))));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));self.clients.claim()});
self.addEventListener("fetch",e=>{
  if(e.request.method!=="GET"||new URL(e.request.url).origin!==location.origin)return;
  const req=e.request.mode==="navigate"?new Request(e.request.url,{cache:"no-cache"}):new Request(e.request,{cache:"no-cache"});
  e.respondWith(fetch(req).then(r=>{if(r.ok){const cp=r.clone();caches.open(CACHE).then(c=>c.put(e.request,cp))}return r}).catch(()=>caches.match(e.request).then(m=>m||caches.match("./index.html"))));
});
