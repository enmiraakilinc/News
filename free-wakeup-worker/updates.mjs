const json = (status, message) => Response.json({message}, {status, headers:{'Cache-Control':'no-store'}});
// Access is granted by the administrator, never by client-writable profiles.
export async function privateUpdates(request, env, {fetch:fetcher=fetch, token}={}) {
  const path = new URL(request.url).pathname;
  if (request.method !== 'GET' || !['/updates/latest','/updates/apk'].includes(path)) return json(404,'İşlem bulunamadı.');
  const auth = request.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ') || auth.length > 10000) return json(401,'Güncelleme için giriş yapmalısın.');
  if (!env.GITHUB_RELEASE_TOKEN || !env.FIREBASE_API_KEY || !env.FIREBASE_PROJECT_ID) return json(503,'Güncelleme hizmeti henüz hazır değil.');
  let stage = 'authentication';
  try {
    const login = await fetcher(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,
      {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idToken:auth.slice(7)})});
    if (!login.ok) return json(401,'Yeniden giriş yapmalısın.');
    const user = (await login.json()).users?.[0];
    const uid = user?.localId;
    if (!uid || user.disabled || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) return json(401,'Yeniden giriş yapmalısın.');
    const admin = await token();
    const base = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
    const get = key => fetcher(`${base}/${key}`, {headers:{Authorization:`Bearer ${admin}`}});
    const access = await get(`updateAccess/${uid}`);
    if (access.status === 404) return json(403,'Bu hesabın güncelleme erişimi yok.');
    if (!access.ok) throw Error('access');
    if ((await access.json()).fields?.enabled?.booleanValue !== true) return json(403,'Bu hesabın güncelleme erişimi yok.');
    const response = await get('config/private_app_version');
    if (!response.ok) return json(503,'Güncelleme henüz hazır değil.');
    const f = (await response.json()).fields;
    const version = f?.name?.stringValue, asset = f?.assetId?.integerValue;
    const repo = env.GITHUB_RELEASE_REPO;
    if (!/^\d+\.\d+\.\d+$/.test(version ?? '') || !/^\d+$/.test(asset ?? '') || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo ?? '')) throw Error('config');
    if (path === '/updates/latest') {
      return Response.json({code:Number(f.code.integerValue),name:version,
        url:new URL(`/updates/apk?version=${version}`,request.url).toString(),
        notes:f.notes?.stringValue ?? '',sha256:f.sha256?.stringValue ?? ''}, {headers:{'Cache-Control':'no-store'}});
    }
    if (new URL(request.url).searchParams.get('version') !== version) return json(409,'Daha yeni bir güncelleme var. Güncelleme ekranını yeniden aç.');
    const headers = {Authorization:`Bearer ${env.GITHUB_RELEASE_TOKEN.trim()}`,Accept:'application/octet-stream','User-Agent':'private-app-updater','X-GitHub-Api-Version':'2022-11-28'};
    stage = 'asset-api';
    let apk = await fetcher(`https://api.github.com/repos/${repo}/releases/assets/${asset}`,{headers,redirect:'manual'});
    if (apk.status === 302) {
      stage = 'asset-redirect';
      const location = new URL(apk.headers.get('Location'));
      if (location.protocol !== 'https:' || !['release-assets.githubusercontent.com','objects.githubusercontent.com'].includes(location.hostname)) throw Error('redirect');
      // Never forward the GitHub token to the asset host or the application.
      stage = 'asset-fetch';
      apk = await fetcher(location.toString(),{redirect:'manual'});
    }
    if (!apk.ok) return Response.json({message:'Güncelleme indirilemiyor. Daha sonra yeniden dene.',code:`upstream-${apk.status}`},{status:503,headers:{'Cache-Control':'no-store'}});
    const output = new Headers({'Content-Type':'application/vnd.android.package-archive','Cache-Control':'private, no-store',
      'Content-Disposition':`attachment; filename="update-${version}.apk"`,'X-Content-Type-Options':'nosniff'});
    const length = apk.headers.get('Content-Length');
    if (length) output.set('Content-Length',length);
    stage = 'asset-stream';
    return new Response(apk.body,{status:200,headers:output});
  } catch { return Response.json({message:'Güncelleme hizmetine şu anda ulaşılamıyor.',code:stage},{status:503,headers:{'Cache-Control':'no-store'}}); }
}
