import {test,beforeEach,afterEach} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import worker from './worker.mjs';

let sql,env,calls,originalFetch,next,telegramFailure;
beforeEach(()=>{
  sql=new DatabaseSync(':memory:');
  sql.exec(readFileSync(new URL('./schema.sql',import.meta.url),'utf8'));
  const prepare=source=>{
    let args=[];
    return {bind(...a){args=a;return this;},
      async run(){const r=sql.prepare(source).run(...args);return {meta:{changes:Number(r.changes)}};},
      async first(){return sql.prepare(source).get(...args)||null;},
      async all(){return {results:sql.prepare(source).all(...args)};},
    };
  };
  env={DB:{prepare,batch:async statements=>{for(const s of statements)await s.run();}},BOT_TOKEN:'test-token',OWNER_ID:'123',WEBHOOK_SECRET:'test-secret',PC_SECRET:'pc-secret'};
  calls=[];next=1000;telegramFailure=false;originalFetch=globalThis.fetch;
  globalThis.fetch=async(url,options)=>{
    const body=JSON.parse(options.body);
    calls.push({url,body});
    if(url.includes('api.github.com')) return new Response(null,{status:204});
    const method=url.split('/').at(-1);
    if(telegramFailure&&method==='deleteMessages') return Response.json({ok:false},{status:400});
    return Response.json({ok:true,result:method==='sendMessage'?{message_id:++next}:true});
  };
});
afterEach(()=>{globalThis.fetch=originalFetch;sql.close();});
async function post(update,secret='test-secret') {
  return worker.fetch(new Request('https://bot.test/telegram',{
    method:'POST',headers:{'X-Telegram-Bot-Api-Secret-Token':secret},body:JSON.stringify(update),
  }),env);
}
let sequence=0;
function message(text,user=123,type='private') {
  const id=++sequence;
  return {update_id:id,message:{message_id:id,from:{id:user},chat:{id:user,type},text}};
}
async function command(text){const u=message(text);assert.equal((await post(u)).status,200);return u;}
async function project(alias='p1') {
  await command(`/proje_ekle ${alias} owner/${alias}`);
  await command(`/proje ${alias}`);
}
async function press(action,nonce) {
  return post({update_id:++sequence,callback_query:{id:'q1',from:{id:123},data:`${action}:${nonce}`,message:{message_id:1000,chat:{id:123,type:'private'}}}});
}
const one=(s,...args)=>sql.prepare(s).get(...args);
test('Wrong webhook secret and unauthorized users cannot read or change tasks',async()=>{
  assert.equal((await post(message('/gorev private'),'wrong')).status,403);
  await post(message('/proje_ekle hacked owner/repo',999));
  await post(message('/proje_ekle group owner/repo',123,'group'));
  assert.equal(one('SELECT count(*) n FROM projects').n,0);
  assert.equal(calls.length,0);
});
test('Project mappings cannot be overwritten and saving Python never executes code',async()=>{
  await project();await command('/proje_ekle p1 attacker/other');
  assert.equal(one('SELECT repo FROM projects WHERE alias=?','p1').repo,'owner/p1');
  await command('/komut_ekle test print("secret")');
  assert.match(calls.at(-1).body.text,/kaydedildi/);
  assert.equal(calls.filter(c=>!c.url.includes('api.telegram.org')).length,0);
});
test('Tasks remain separated by project and sensitive text is not echoed in lists',async()=>{
  await project();const u=await command('/gorev Gizli özellik açıklaması');
  await command('/gorevler');assert.doesNotMatch(calls.at(-1).body.text,/Gizli özellik/);
  await project('p2');await command(`/goster t${u.update_id}`);
  assert.match(calls.at(-1).body.text,/bulunamadı/);
  await command(`/sil t${u.update_id}`);
  assert.equal(one('SELECT count(*) n FROM confirmations').n,0);
  await command('/gorevler');assert.match(calls.at(-1).body.text,/istek yok/);
});
test('Confirmation binds action and original project despite switching projects',async()=>{
  await project();const u=await command('/gorev Delete me');
  await command(`/sil t${u.update_id}`);
  const c=one('SELECT * FROM confirmations');
  assert.equal((await press('build',c.nonce)).status,200);
  assert.equal(one('SELECT count(*) n FROM tasks').n,1);
  await project('p2');await command('/gorev Keep me');
  await press('erase',c.nonce);
  assert.equal(one('SELECT count(*) n FROM tasks WHERE project=?','p1').n,0);
  assert.equal(one('SELECT body FROM tasks WHERE project=?','p2').body,'Keep me');
  assert.ok(calls.some(c=>c.url.endsWith('/deleteMessages')));
  const previous=calls.filter(c=>c.url.endsWith('/deleteMessages')).length;
  await press('erase',c.nonce);
  assert.equal(calls.filter(c=>c.url.endsWith('/deleteMessages')).length,previous);
});
test('Deletion removes task text even when Telegram fails and retains message IDs for retry',async()=>{
  await project();const u=await command('/gorev Private text');
  await command(`/sil t${u.update_id}`);const c=one('SELECT * FROM confirmations');
  telegramFailure=true;await press('erase',c.nonce);
  assert.equal(one('SELECT count(*) n FROM tasks').n,0);
  assert.ok(one('SELECT count(*) n FROM messages WHERE task=?',`t${u.update_id}`).n>0);
  assert.match(calls.at(-1).body.text,/tekrar denenecek/);
});
test('Old Telegram messages are not falsely reported as deleted',async()=>{
  await project();await command('/gorev private');
  sql.prepare('UPDATE messages SET created=?').run(Math.floor(Date.now()/1000)-3*86400);
  await command('/temizle');await press('erase',one('SELECT nonce FROM confirmations').nonce);
  assert.equal(one('SELECT count(*) n FROM tasks').n,0);
  assert.ok(one('SELECT count(*) n FROM messages').n>0);
  assert.match(calls.at(-1).body.text,/Eski: [1-9]/);
});
test('Duplicate Telegram delivery creates one task and expiration blocks confirmation',async()=>{
  await project();const u=message('/gorev exactly once stored');
  await post(u);await post(u);
  assert.equal(one('SELECT count(*) n FROM tasks').n,1);
  await command('/temizle');const c=one('SELECT * FROM confirmations');
  sql.prepare('UPDATE confirmations SET created=?').run(0);
  await press('erase',c.nonce);
  assert.equal(one('SELECT count(*) n FROM tasks').n,1);
});
test('Build needs explicit confirmation, configuration, and dispatches only selected workflow',async()=>{
  await project();await command('/derleme_ayarla build.yml main');
  await command('/derle');const c=one('SELECT * FROM confirmations');
  assert.equal(calls.filter(c=>c.url.includes('api.github.com')).length,0);
  env.GITHUB_TOKEN='test-github-token';
  await press('build',c.nonce);
  const dispatch=calls.find(c=>c.url.includes('api.github.com'));
  assert.ok(dispatch.url.endsWith('/owner/p1/actions/workflows/build.yml/dispatches'));
  assert.deepEqual(dispatch.body,{ref:'main'});
  assert.match(calls.at(-1).body.text,/sonuç henüz doğrulanmadı/);
});
test('No emulator or coding agent is falsely advertised',async()=>{
  delete env.PC_SECRET;
  await project();
  await command('/ss');assert.match(calls.at(-1).body.text,/bağlı değil/);
  await command('/durum');assert.match(calls.at(-1).body.text,/yalnızca yerel ayarlarda izin verilen/);
  assert.equal(calls.filter(c=>!c.url.includes('api.telegram.org')).length,0);
});
test('Normal messages create scoped coding jobs and heartbeat requires current lease',async()=>{
  await project();
  const update=await command('Başlık rengini düzelt');
  const saved=one('SELECT * FROM pc_jobs WHERE id=?',`t${update.update_id}`);
  assert.equal(saved.kind,'codex');
  assert.equal(saved.project,'p1');
  assert.equal(JSON.parse(saved.payload).prompt,'Başlık rengini düzelt');
  const response=await pc('/pc/ping',{project:'p1'});
  const {job}=await response.json();
  assert.equal((await pc('/pc/heartbeat',{project:'p1',id:job.id,lease:'wrong'})).status,409);
  assert.equal((await pc('/pc/heartbeat',{project:'p1',id:job.id,lease:job.lease})).status,200);
  await command('/eklenecek Sadece not');
  assert.equal(one('SELECT count(*) n FROM pc_jobs').n,1);
});
async function pc(path,body,secret='pc-secret') {
  return worker.fetch(new Request('https://bot.test'+path,{method:'POST',headers:{Authorization:'Bearer '+secret},body:JSON.stringify(body)}),env);
}
test('PC queue requires independent authentication and binds jobs to the requested project',async()=>{
  env.PC_SECRET='pc-secret';await project();await command('/ss');
  assert.equal((await pc('/pc/ping',{project:'p1'},'wrong')).status,403);
  await project('p2');
  assert.equal((await (await pc('/pc/ping',{project:'p2'})).json()).job,null);
  const first=await (await pc('/pc/ping',{project:'p1'})).json();
  assert.equal(first.job.kind,'screenshot');
  assert.equal((await (await pc('/pc/ping',{project:'p1'})).json()).job,null);
  assert.equal((await pc('/pc/result',{project:'p1',id:first.job.id,lease:'wrong',text:'ok'})).status,409);
  assert.equal((await pc('/pc/result',{project:'p1',id:first.job.id,lease:first.job.lease,text:'No desktop session'})).status,200);
  assert.equal(one('SELECT state FROM pc_jobs').state,'done');
  assert.equal(one('SELECT payload FROM pc_jobs').payload,'');
});
test('Python commands require confirmation and deleting a project cancels its pending jobs only',async()=>{
  env.PC_SECRET='pc-secret';await project();
  await command('/komut_ekle hello print("Hello")');await command('/calistir hello');
  assert.equal((await (await pc('/pc/ping',{project:'p1'})).json()).job,null);
  const confirmation=one('SELECT * FROM confirmations');
  await press('pc',confirmation.nonce);
  const job=(await (await pc('/pc/ping',{project:'p1'})).json()).job;
  assert.equal(job.kind,'python');assert.equal(job.payload.code,'print("Hello")');
  await project('p2');await command('/komut_ekle other print(2)');await command('/ss');
  await command('/proje p1');await command('/temizle');
  await press('erase',one("SELECT nonce FROM confirmations WHERE action='erase'").nonce);
  assert.equal(one("SELECT count(*) n FROM pc_jobs WHERE project='p1'").n,0);
  assert.equal(one("SELECT count(*) n FROM commands WHERE project='p1'").n,0);
  assert.equal(one("SELECT count(*) n FROM pc_jobs WHERE project='p2'").n,1);
  assert.equal((await pc('/pc/result',{project:'p1',id:job.id,lease:job.lease,text:'late output'})).status,404);
});
test('Expired PC lease can be reclaimed but an old agent result is rejected',async()=>{
  env.PC_SECRET='pc-secret';await project();await command('/ss');
  const old=(await (await pc('/pc/ping',{project:'p1'})).json()).job;
  sql.prepare('UPDATE pc_jobs SET lease_until=0').run();
  const fresh=(await (await pc('/pc/ping',{project:'p1'})).json()).job;
  assert.equal(fresh.id,old.id);assert.notEqual(fresh.lease,old.lease);
  assert.equal((await pc('/pc/result',{project:'p1',id:old.id,lease:old.lease,text:'old'})).status,409);
});
test('Menu shortcuts keep the original update identity and canceled commands do not stay queued',async()=>{
  env.PC_SECRET='pc-secret';await project();
  await command('/komut_ekle c print(1)');await command('/calistir c');
  await press('cancel',one('SELECT nonce FROM confirmations').nonce);
  assert.equal(one('SELECT count(*) n FROM pc_jobs').n,0);
  await press('menu','ss');
  assert.equal(one('SELECT kind FROM pc_jobs').kind,'screenshot');
});
test('Deleting a command tolerates erased payloads from completed jobs',async()=>{
  env.PC_SECRET='pc-secret';await project();
  await command('/komut_ekle done print(1)');
  sql.prepare("INSERT INTO pc_jobs(id,project,kind,payload,state,created) VALUES('old','p1','python','','done',0)").run();
  await command('/komut_sil done');
  assert.equal(one('SELECT count(*) n FROM commands').n,0);
});
test('Menu contains only project features and interview shortcuts are removed',async()=>{
  await command('/start');
  const response=calls.at(-1).body;
  assert.doesNotMatch(response.text,/mülakat|\/soru|\/cevap/i);
  assert.ok(response.reply_markup.inline_keyboard.flat().every(b=>!b.callback_data.includes('question')&&!b.callback_data.includes('answer')));
  await project();await command('/soru');
  assert.match(calls.at(-1).body.text,/tanınmadı/);
});
