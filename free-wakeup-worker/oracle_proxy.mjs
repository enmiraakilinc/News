let cached;
export async function oracleMode(fetcher=fetch){
 if(cached&&cached.until>Date.now())return cached.primary;
 try{
  const response=await fetcher('https://138.2.185.151/v1/capabilities',{signal:AbortSignal.timeout(5000)});
  if(!response.ok)throw Error('capabilities');
  const data=await response.json();
  if(typeof data.primaryWrites!=='boolean')throw Error('capabilities');
  cached={primary:data.primaryWrites,until:Date.now()+5000};return cached.primary;
 }catch{return cached?.primary===true?true:null;}
}
export async function proxyOracle(request,env,{fetch:fetcher=fetch,scheduledUid}={}){
 if(!env.NEURAL_PUSH_SECRET)return null;
 const mode=await oracleMode(fetcher);
 if(mode===false)return null;
 if(mode===null)return Response.json({message:'Sunucuya şu anda ulaşılamıyor. Biraz sonra dene.'},{status:503});
 const url=new URL(request.url),headers={'content-type':'application/json'};
 let path=url.pathname,body=await request.text();
 if(body.length>4096)return new Response('',{status:413});
 if(scheduledUid){
  const value=JSON.parse(body);value.uid=scheduledUid;body=JSON.stringify(value);path='/internal/legacy-wake';
  const time=String(Date.now());
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env.NEURAL_PUSH_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const signature=new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(time+'\nlegacy-wake\n'+body)));
  headers['x-neural-time']=time;headers['x-neural-signature']=Array.from(signature,v=>v.toString(16).padStart(2,'0')).join('');
 }else{headers.authorization=request.headers.get('authorization')??'';}
 try{
  const response=await fetcher('https://138.2.185.151'+path,{method:'POST',headers,body,signal:AbortSignal.timeout(20000)});
  const result=await response.json();
  return Response.json({message:result.message??result.error?.message??'İşlem tamamlanamadı.',...(result.email?{email:result.email}:{})},{status:response.status,headers:{'cache-control':'no-store'}});
 }catch{return Response.json({message:'Sunucuya şu anda ulaşılamıyor. Biraz sonra dene.'},{status:503});}
}
