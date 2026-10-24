import {createHmac,randomUUID} from 'node:crypto';
// Firebase credentials stay on the existing Worker; only FCM transport remains there.
export async function deliverPush(message,{fetcher=fetch,secret=process.env.NEURAL_PUSH_SECRET,url=process.env.NEURAL_PUSH_URL}={}){
 if(!secret||!url)throw Error('push_transport_not_configured');
 const target=new URL(url);
 if(target.protocol!=='https:'||target.pathname!=='/internal/push')throw Error('push_transport_invalid');
 const body=JSON.stringify({id:randomUUID(),message}),time=String(Date.now());
 const signature=createHmac('sha256',secret).update(time+'\n'+body).digest('hex');
 const response=await fetcher(target,{method:'POST',headers:{'content-type':'application/json','x-neural-time':time,'x-neural-signature':signature},body,signal:AbortSignal.timeout(10000)});
 return response.ok;
}
