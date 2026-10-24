import {createHmac,timingSafeEqual} from 'node:crypto';
import {ApiError} from './access.mjs';
export function authenticateLegacyWake(headers,raw,{secret=process.env.NEURAL_PUSH_SECRET,now=Date.now()}={}){
 const time=headers['x-neural-time']??'',signature=headers['x-neural-signature']??'';
 if(!secret||!/^\d{13}$/.test(time)||Math.abs(now-Number(time))>60000||!/^[a-f0-9]{64}$/.test(signature)||raw.length>4096)throw new ApiError(401,'unauthenticated','İstek doğrulanamadı.');
 const expected=createHmac('sha256',secret).update(time+'\nlegacy-wake\n'+raw).digest();
 if(!timingSafeEqual(expected,Buffer.from(signature,'hex')))throw new ApiError(401,'unauthenticated','İstek doğrulanamadı.');
 const body=JSON.parse(raw);
 if(!/^[A-Za-z0-9_-]{1,128}$/.test(body.uid??'')||!/^[a-f0-9-]{36}$/.test(body.eventId??'')||!Number.isSafeInteger(body.fireAt)||now-body.fireAt<0||now-body.fireAt>90000)throw new ApiError(400,'invalid-argument','Uyandırma süresi doldu.');
 return body;
}
