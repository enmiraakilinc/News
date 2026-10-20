// Codes are login identifiers, never a substitute for the Firebase password.
// No passwords pass through this worker; alias documents stay owner-only.
export async function resolveAccount(request, env, {fetch: fetcher=fetch, token}={}) {
  const reply=(status,message)=>Response.json({message},{status});
  const auth=request.headers.get('Authorization')??'';
  if(!auth.startsWith('Bearer ')||auth.length>10000) return reply(401,'Yeniden giriş yapmalısın.');
  try {
    const raw=await request.text();
    if(raw.length>256) return reply(400,'Hesap kodunu kontrol et.');
    const body=JSON.parse(raw);
    if(typeof body.code!=='string'||!/^\d{12}$/.test(body.code)) return reply(400,'Hesap kodunu kontrol et.');
    const reserve=async (key,limit)=>{
      const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key));
      const name=Array.from(new Uint8Array(digest),v=>v.toString(16).padStart(2,'0')).join('');
      const object=env.WAKE_RATE.get(env.WAKE_RATE.idFromName(`account-rate:${name}`));
      return (await object.fetch(new Request('https://internal/account/reserve',{method:'POST',body:JSON.stringify({limit})}))).ok;
    };
    if(!await reserve(`ip:${request.headers.get('CF-Connecting-IP')??'unknown'}`,20)) return reply(429,'Çok fazla deneme yapıldı. 10 dakika sonra yeniden dene.');
    const login=await fetcher(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idToken:auth.slice(7)})});
    if(!login.ok) return reply(401,'Yeniden giriş yapmalısın.');
    const uid=(await login.json()).users?.[0]?.localId;
    if(!uid) return reply(401,'Yeniden giriş yapmalısın.');
    if(!await reserve(`uid:${uid}`,10)||!await reserve(`code:${body.code}`,6)) return reply(429,'Çok fazla deneme yapıldı. 10 dakika sonra yeniden dene.');
    const r=await fetcher(`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/accountCodeAliases/${body.code}`,{headers:{Authorization:`Bearer ${await token()}`}});
    if(r.status===404) return reply(404,'Hesap kodu veya şifre yanlış.');
    if(!r.ok) throw Error('lookup');
    const email=(await r.json()).fields?.email?.stringValue;
    if(typeof email!=='string'||!email.match(/^[a-f0-9]{32}@accounts\.neural\.invalid$/)) throw Error('invalid-alias');
    // Do not return owner UID, tokens or any other document field.
    return Response.json({email});
  } catch(_) { return reply(503,'Hesap bağlantısı kurulamadı. Yeniden dene.'); }
}
