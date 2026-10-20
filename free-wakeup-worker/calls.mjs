export async function notifyCall(request, env, {fetch: fetcher, token}) {
  const reply=(status,message)=>Response.json({message},{status});
  const auth=request.headers.get('Authorization')??'';
  if(!auth.startsWith('Bearer ')||auth.length>10000)return reply(401,'Yeniden giriş yapmalısın.');
  try {
    const raw=await request.text();if(raw.length>1024)return reply(400,'Geçersiz arama.');
    let body;try{body=JSON.parse(raw);}catch{return reply(400,'Geçersiz arama.');}
    if(!/^[A-Za-z0-9]{20}$/.test(body.id??'')||!['ring','end'].includes(body.action))return reply(400,'Geçersiz arama.');
    const login=await fetcher(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,
      {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idToken:auth.slice(7)})});
    if(!login.ok)return reply(401,'Yeniden giriş yapmalısın.');
    const uid=(await login.json()).users?.[0]?.localId;
    const access=await token();
    const base=`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
    const api=(url,options={})=>fetcher(url,{...options,headers:{Authorization:`Bearer ${access}`,'Content-Type':'application/json'}});
    const response=await api(`${base}/voiceCalls/${body.id}`);
    if(!response.ok)return reply(404,'Arama sona ermiş.');
    const call=(await response.json()).fields;
    const caller=call?.caller?.stringValue,callee=call?.callee?.stringValue;
    if(!uid||![caller,callee].includes(uid)||caller===callee)return reply(403,'Bu aramaya erişemezsin.');
    const kind=call.sourceType?.stringValue,id=call.sourceId?.stringValue;
    if(!['chat','couple'].includes(kind)||!/^[A-Za-z0-9_-]{1,200}$/.test(id??''))return reply(403,'Sohbet bulunamadı.');
    const source=await api(`${base}/${kind==='chat'?'chats':'couples'}/${id}`);
    if(!source.ok)return reply(403,'Sohbet bulunamadı.');
    const members=(await source.json()).fields?.members?.arrayValue?.values?.map(v=>v.stringValue)??[];
    if(members.length!==2||!members.includes(caller)||!members.includes(callee))return reply(403,'Bu aramaya erişemezsin.');
    const ringing=body.action==='ring';
    const age=Date.now()-Date.parse(call.createdAt?.timestampValue);
    if(ringing&&(uid!==caller||call.state?.stringValue!=='ringing'||!Number.isFinite(age)||age < -5000||age>45000))return reply(409,'Arama sona ermiş.');
    if(!ringing&&call.state?.stringValue!=='ended')return reply(409,'Arama henüz sona ermemiş.');
    const recipient=ringing?callee:(uid===caller?callee:caller);
    const devices=await api(`${base}/chatAccounts/${recipient}:runQuery`,{method:'POST',body:JSON.stringify({structuredQuery:{from:[{collectionId:'callDevices'}],where:{fieldFilter:{field:{fieldPath:'enabled'},op:'EQUAL',value:{booleanValue:true}}},limit:5}})});
    if(!devices.ok)throw Error('devices');
    let count=0;
    for(const entry of await devices.json()){
      const fields=entry.document?.fields;
      if(fields?.enabled?.booleanValue!==true||!fields?.token?.stringValue)continue;
      const result=await api(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`,{method:'POST',body:JSON.stringify({message:{token:fields.token.stringValue,data:{type:ringing?'voice_call':'voice_call_end',callId:body.id,recipientUid:recipient},android:{priority:'HIGH',ttl:'45s',collapse_key:`call_${body.id}`}}})});
      if(result.ok)count++;
    }
    return reply(200,count?'Arama bildirimi iletildi.':'Uygulama kapalıyken arama alma açık değil; açık uygulamaya arama iletilir.');
  }catch{return reply(503,'Arama bildirimi şu anda iletilemedi.');}
}
