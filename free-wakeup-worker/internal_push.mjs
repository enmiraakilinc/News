// A signed VPS request can use FCM transport without receiving Google credentials.
export async function internalPush(request,env,{fetch:fetcher=fetch,token}){
 const reject=status=>new Response('',{status});
 if(request.method!=='POST')return reject(405);
 if(!env.NEURAL_PUSH_SECRET)return reject(503);
 const time=request.headers.get('x-neural-time')??'',signature=request.headers.get('x-neural-signature')??'';
 if(!/^\d{13}$/.test(time)||Math.abs(Date.now()-Number(time))>60000||!/^[a-f0-9]{64}$/.test(signature))return reject(401);
 const raw=await request.text();if(raw.length>16384)return reject(413);
 const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env.NEURAL_PUSH_SECRET),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 const bytes=Uint8Array.from(signature.match(/../g),v=>parseInt(v,16));
 if(!await crypto.subtle.verify('HMAC',key,bytes,new TextEncoder().encode(time+'\n'+raw)))return reject(401);
 let body;try{body=JSON.parse(raw);}catch{return reject(400);}
 const message=body.message;
 if(!/^[a-f0-9-]{36}$/.test(body.id??'')||typeof message?.token!=='string'||message.token.length<20||message.token.length>4096
  ||!['wake','voice_call','voice_call_end'].includes(message.data?.type)
  ||Object.values(message.data).some(v=>typeof v!=='string'||v.length>1024)||Object.keys(message.data).length>12
  ||Object.keys(message).some(k=>!['token','data','android'].includes(k))
  ||message.android?.priority!=='HIGH'||!['45s','60s'].includes(message.android?.ttl)
  ||Object.keys(message.android??{}).some(k=>!['priority','ttl','collapse_key'].includes(k)))return reject(400);
 const guard=env.WAKE_RATE.get(env.WAKE_RATE.idFromName('vps-push:'+body.id));
 if(!(await guard.fetch(new Request('https://internal/account/reserve',{method:'POST',body:JSON.stringify({limit:1})}))).ok)return reject(409);
 const response=await fetcher('https://fcm.googleapis.com/v1/projects/'+env.FIREBASE_PROJECT_ID+'/messages:send',{
  method:'POST',headers:{Authorization:'Bearer '+await token(),'content-type':'application/json'},body:JSON.stringify({message})
 });
 return reject(response.ok?200:503);
}
