import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {authenticateLegacyWake} from '../src/legacy_wake.mjs';
test('legacy wake signature is bound to its purpose, timestamp and short-lived plan',()=>{
 const secret='test-only-secret',now=Date.now();
 const body={uid:'owner',eventId:'00000000-0000-4000-8000-000000000000',fireAt:now-1000},raw=JSON.stringify(body),time=String(now);
 const sign=purpose=>createHmac('sha256',secret).update(time+'\n'+purpose+raw).digest('hex');
 const headers={'x-neural-time':time,'x-neural-signature':sign('legacy-wake\n')};
 assert.deepEqual(authenticateLegacyWake(headers,raw,{secret,now}),body);
 assert.throws(()=>authenticateLegacyWake({...headers,'x-neural-signature':sign('')},raw,{secret,now}));
 assert.throws(()=>authenticateLegacyWake(headers,raw,{secret,now:now+120000}));
 assert.throws(()=>authenticateLegacyWake(headers,raw+' ',{secret,now}));
});
