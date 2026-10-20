const now = () => Math.floor(Date.now()/1000);
const aliasOK = s => /^[a-z0-9][a-z0-9_-]{0,23}$/.test(s);
const repoOK = s => /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(s) && !s.includes('..');
const help = `Proje asistanı
/proje_ekle kod sahip/depo — proje tanımla
/projeler — projelerim
/proje kod — proje seç
/gorev açıklama — istek kaydet
/gorevler — seçili projenin son 15 istek kimliği
/goster görev-kimliği — isteği görüntüle
/sil görev-kimliği — isteği ve ilişkili mesajları silmek için onay iste
/temizle — seçili projenin kayıtlarını/mesajlarını temizlemek için onay iste
/derleme_ayarla workflow.yml dal — mevcut GitHub derleme işini bağla
/derle — derleme için onay iste
/durum — çalışma sınırları
/ss — bağlı PC'den bir defalık ekran görüntüsü iste
/gitpull — bağlı PC'de git pull --ff-only için onay iste
/takip göreli-dosya.log — PC'de hata günlüğü takibini seç
/hatalar — bağlı PC'nin son hata raporu
/komut_ekle ad python-kodu — projeye özel Python komutu kaydet
/komutlar — özel komutları listele
/calistir ad — bağlı PC'de özel komut için onay iste
/komut_sil ad — özel komutu kaldır
Kod yazan yapay zekâ bağlı değil. Görev kaydı kodu değiştirmez.
Silme Git geçmişini, harici logları ve teslim edilmiş işleri geri almaz.
Telegram silme sınırı 48 saattir; eski mesajları Telegram'dan elle temizle.`;

function db(env) {
  return {
    run: (sql,...a) => env.DB.prepare(sql).bind(...a).run(),
    one: (sql,...a) => env.DB.prepare(sql).bind(...a).first(),
    all: async (sql,...a) => (await env.DB.prepare(sql).bind(...a).all()).results,
  };
}
async function telegram(env,method,body) {
  const r = await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/${method}`,{
    method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify(body),signal:AbortSignal.timeout(12000),
  });
  const data=await r.json();
  if(!r.ok || !data.ok) throw new Error('Telegram request failed');
  return data.result;
}
async function track(store,chat,id,project,task=null) {
  await store.run('INSERT OR IGNORE INTO messages VALUES(?,?,?,?,?)',chat,id,project,task,now());
}
async function send(env,store,chat,project,text,task=null,markup=undefined) {
  const result=await telegram(env,'sendMessage',{
    chat_id:chat,text:text.slice(0,4000),protect_content:true,
    ...(markup?{reply_markup:markup}:{}),
  });
  await track(store,chat,result.message_id,project,task);
}
async function confirm(env,store,chat,project,task,action) {
  const nonce=crypto.randomUUID();
  await store.run('INSERT INTO confirmations VALUES(?,?,?,?,?)',nonce,project,task,action,now());
  await send(env,store,chat,project,
    action==='pc'
      ? 'Bu PC işlemi seçili proje klasöründe çalışacak. Bilgisayar kapalıysa sırada bekler. Özel Python komutu için PC ajanında kod çalıştırma ayrıca açık olmalı. Devam edilsin mi?'
      : action==='build'
      ? 'Bağlı GitHub işini başlatayım mı? Kota kullanılır. Yalnızca derleme yapan bir workflow seçilmeli; bot yayın komutu göndermez.'
      : 'Bot kaydı silinsin ve ilgili Telegram mesajları silinmeye çalışılsın mı? Kod, Git geçmişi, loglar ve teslim edilmiş işler etkilenmez.',
    task,{inline_keyboard:[[
      {text:action==='build'?'Derlemeyi başlat':action==='pc'?'Çalıştır':'Sil',callback_data:`${action}:${nonce}`},
      {text:'Vazgeç',callback_data:`cancel:${nonce}`},
    ]]});
}
async function cleanup(env,store,chat,project,task=null) {
  if(task) {
    await store.run('DELETE FROM tasks WHERE project=? AND id=?',project,task);
    await store.run('DELETE FROM pc_jobs WHERE project=? AND id=?',project,task);
  }
  else {
    await env.DB.batch([
      env.DB.prepare('DELETE FROM tasks WHERE project=?').bind(project),
      env.DB.prepare('DELETE FROM pc_jobs WHERE project=?').bind(project),
      env.DB.prepare('DELETE FROM commands WHERE project=?').bind(project),
      env.DB.prepare('DELETE FROM pc_status WHERE project=?').bind(project),
      env.DB.prepare('DELETE FROM confirmations WHERE project=?').bind(project),
    ]);
  }
  const rows=await store.all(`SELECT * FROM messages WHERE chat=? AND project=?${task?' AND task=?':''} ORDER BY created DESC LIMIT 500`,chat,project,...(task?[task]:[]));
  const recent=rows.filter(r=>now()-r.created<48*3600);
  let accepted=0;
  for(let i=0;i<recent.length;i+=90) {
    const ids=recent.slice(i,i+90).map(r=>r.id);
    try {
      await telegram(env,'deleteMessages',{chat_id:chat,message_ids:ids});
      await store.run(`DELETE FROM messages WHERE chat=? AND id IN (${ids.map(()=>'?').join(',')})`,chat,...ids);
      accepted+=ids.length;
    } catch { /* Keep IDs for retry. Never log Telegram responses or tokens. */ }
  }
  return `İstek kayıtları temizlendi. ${accepted} mesajlık silme talebi Telegram tarafından kabul edildi (tek tek silinme teyidi verilmez). Eski: ${rows.length-recent.length}; tekrar denenecek: ${recent.length-accepted}.${rows.length===500?' Daha fazlası için temizlemeyi tekrarla.':''}`;
}
async function callback(env,store,q) {
  const chat=q.message.chat.id;
  const shortcuts={projects:'/projeler',status:'/durum',ss:'/ss',pull:'/gitpull',errors:'/hatalar',commands:'/komutlar',tasks:'/gorevler',clear:'/temizle'};
  if((q.data||'').startsWith('menu:')) {
    const text=shortcuts[q.data.slice(5)];
    if(!text) return;
    await telegram(env,'answerCallbackQuery',{callback_query_id:q.id});
    return processUpdate(env,{update_id:q.update_id,message:{...q.message,from:q.from,text}});
  }
  const [action,nonce]=(q.data||'').split(':');
  const saved=await store.one('SELECT * FROM confirmations WHERE nonce=?',nonce||'');
  if(!saved || now()-saved.created>300 || (action!==saved.action && action!=='cancel')) {
    await telegram(env,'answerCallbackQuery',{callback_query_id:q.id,text:'Onay geçersiz veya süresi dolmuş.'});
    return;
  }
  const claim=await store.run('DELETE FROM confirmations WHERE nonce=?',nonce);
  if(claim.meta.changes!==1) return;
  await telegram(env,'answerCallbackQuery',{callback_query_id:q.id});
  if(action==='cancel') {
    if(saved.action==='pc') await store.run("DELETE FROM pc_jobs WHERE id=? AND project=? AND state='confirm'",saved.task,saved.project);
    return send(env,store,chat,saved.project,'İptal edildi.');
  }
  if(action==='erase') return send(env,store,chat,saved.project,await cleanup(env,store,chat,saved.project,saved.task));
  if(action==='pc') {
    const job=await store.one("SELECT id FROM pc_jobs WHERE id=? AND project=? AND state='confirm'",saved.task,saved.project);
    if(!job) return send(env,store,chat,saved.project,'PC işlemi artık mevcut değil.');
    await store.run("UPDATE pc_jobs SET state='pending' WHERE id=? AND state='confirm'",job.id);
    return send(env,store,chat,saved.project,`PC işlemi sıraya alındı: ${job.id}. Tamamlanma sonucu ayrıca gelecek.`,job.id);
  }
  const p=await store.one('SELECT * FROM projects WHERE alias=?',saved.project);
  if(!p?.workflow || !env.GITHUB_TOKEN) return send(env,store,chat,saved.project,'Derleme bağlı değil. Workflow ve sınırlı GitHub tokenı gerekli.');
  const response=await fetch(`https://api.github.com/repos/${p.repo}/actions/workflows/${encodeURIComponent(p.workflow)}/dispatches`,{
    method:'POST',headers:{Authorization:`Bearer ${env.GITHUB_TOKEN}`,'User-Agent':'private-project-assistant',Accept:'application/vnd.github+json','content-type':'application/json'},
    body:JSON.stringify({ref:p.ref}),signal:AbortSignal.timeout(12000),
  });
  await send(env,store,chat,saved.project,response.ok
    ? `Derleme tetiklendi; sonuç henüz doğrulanmadı.\nhttps://github.com/${p.repo}/actions`
    : 'Derleme başlatılamadı. Depo yetkisi, workflow ve dalı kontrol et.');
}

export async function processUpdate(env,update) {
  const m=update.message||update.callback_query?.message;
  const user=update.callback_query?.from||update.message?.from;
  if(!m || m.chat?.type!=='private' || String(user?.id)!==String(env.OWNER_ID) || String(m.chat.id)!==String(env.OWNER_ID)) return;
  const store=db(env);
  const selected=await store.one("SELECT value FROM settings WHERE key='selected'");
  const project=selected?.value||'';
  if(update.callback_query) return callback(env,store,{...update.callback_query,update_id:update.update_id});
  const text=m.text||'';
  const [raw,...args]=text.trim().split(/\s+/);
  const command=raw.toLowerCase().split('@')[0];
  const reply=(s,task=null)=>send(env,store,m.chat.id,project,s,task);
  await track(store,m.chat.id,m.message_id,project);
  if(command==='/kilavuz') return reply(help);
  if(['/start','/menu'].includes(command)) return send(env,store,m.chat.id,project,`Seçili proje: ${project||'yok'}\nYapılmasını istediğini normal mesaj olarak yaz. Bilgisayar ve yerel Codex bağlantısı açıkken proje dosyaları düzenlenir; VS Code'da görebilirsin. Yayınlama otomatik yapılmaz. Mevcut Codex kotan kullanılır.\nProje değiştirmek: /proje uygulama veya /proje bot\nDiğer komutlar: /kilavuz`,null,{inline_keyboard:[
    [{text:'Projeler',callback_data:'menu:projects'},{text:'Durum',callback_data:'menu:status'}],
    [{text:'PC ekranı',callback_data:'menu:ss'}],
    [{text:'İstekler',callback_data:'menu:tasks'},{text:'Geçmişi temizle',callback_data:'menu:clear'}],
  ]});
  if(command==='/proje_ekle') {
    if(args.length!==2 || !aliasOK(args[0]) || !repoOK(args[1])) return reply('Kullanım: /proje_ekle kisa-kod sahip/depo');
    await store.run('INSERT OR IGNORE INTO projects(alias,repo) VALUES(?,?)',args[0],args[1]);
    return reply('Proje kaydı hazır. /proje kod ile seç. Mevcut eşleme değiştirilmedi.');
  }
  if(command==='/projeler') {
    const projects=await store.all('SELECT alias FROM projects ORDER BY alias LIMIT 50');
    return reply(projects.length?projects.map(p=>`${p.alias===project?'✓ ':''}${p.alias}`).join('\n'):'Henüz proje yok. /proje_ekle kod sahip/depo');
  }
  if(command==='/proje') {
    const p=await store.one('SELECT alias FROM projects WHERE alias=?',args[0]||'');
    if(!p) return reply('Proje bulunamadı. /projeler ile listele.');
    await store.run("INSERT INTO settings VALUES('selected',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",p.alias);
    return send(env,store,m.chat.id,p.alias,`Seçili proje: ${p.alias}`);
  }
  if(command==='/durum') {
    const status=await store.one('SELECT seen FROM pc_status WHERE project=?',project);
    return reply(`Proje: ${project||'seçilmedi'}\nPC ajanı: ${status && now()-status.seen<90?'bağlı':'bağlantı yok'}\nKod görevleri yalnızca yerel ayarlarda izin verilen projede bilgisayarındaki Codex ile çalışır. VS Code açık olmak zorunda değil. Mevcut Codex kotan kullanılır. Bulut emülatörü bağlı değil. Yayınlama otomatik yapılmaz.`);
  }
  if(!project) return reply('Önce /proje kod ile proje seç.');
  if(command==='/komut_ekle') {
    const name=args[0]||'';
    const code=text.trim().slice(raw.length).trim().slice(name.length).trim();
    if(!aliasOK(name)||!code||code.length>3000) return reply('Kullanım: /komut_ekle ad python-kodu (en fazla 3000 karakter)');
    await store.run('INSERT INTO commands VALUES(?,?,?) ON CONFLICT(project,name) DO UPDATE SET code=excluded.code',project,name,code);
    return reply('Özel komut kaydedildi. /calistir ad ile onaylı çalıştırılır.');
  }
  if(command==='/komutlar') {
    const commands=await store.all('SELECT name FROM commands WHERE project=? ORDER BY name LIMIT 50',project);
    return reply(commands.length?commands.map(c=>c.name).join('\n'):'Bu projede özel komut yok.');
  }
  if(command==='/komut_sil') {
    await store.run('DELETE FROM commands WHERE project=? AND name=?',project,args[0]||'');
    // Also cancel undispatched copies of the deleted command.
    await store.run("DELETE FROM pc_jobs WHERE project=? AND kind='python' AND json_extract(CASE WHEN json_valid(payload) THEN payload ELSE '{}' END,'$.name')=? AND state IN ('confirm','pending')",project,args[0]||'');
    return reply('Komut ve ona ait bekleyen işler kaldırıldı. Teslim edilmiş iş geri alınamaz.');
  }
  if(command==='/hatalar') {
    const status=await store.one('SELECT last_error FROM pc_status WHERE project=?',project);
    return reply(status?.last_error||'PC ajanından hata raporu alınmadı; bu projenin hatasız olduğu anlamına gelmez.');
  }
  if(['/ss','/gitpull','/takip','/calistir'].includes(command)) {
    if(!env.PC_SECRET) return reply('PC bağlantısı henüz yapılandırılmadı. PC_SECRET ve yeni PC ajanı gerekli. Bulut emülatörü bağlı değil.');
    let kind,payload={};
    if(command==='/ss') kind='screenshot';
    if(command==='/gitpull') {
      kind='gitpull';
      payload={repo:(await store.one('SELECT repo FROM projects WHERE alias=?',project)).repo};
    }
    if(command==='/takip') {
      const path=args[0]||'';
      if(!/^[A-Za-z0-9_./-]{1,160}$/.test(path)||path.startsWith('/')||path.split('/').includes('..')) return reply('Proje içindeki göreli günlük veya .py dosyasını yaz: /takip logs/app.log');
      kind='watch';payload={path};
    }
    if(command==='/calistir') {
      const c=await store.one('SELECT code FROM commands WHERE project=? AND name=?',project,args[0]||'');
      if(!c) return reply('Bu projede özel komut bulunamadı. /komutlar');
      kind='python';payload={name:args[0],code:c.code};
    }
    const count=await store.one('SELECT count(*) n FROM pc_jobs WHERE project=?',project);
    if(count.n>=50) return reply('PC kuyruğu dolu. Önce gereksiz kayıtları temizle.');
    const id=`pc${update.update_id}`;
    await store.run('INSERT OR IGNORE INTO pc_jobs(id,project,kind,payload,state,created) VALUES(?,?,?,?,?,?)',id,project,kind,JSON.stringify(payload),['screenshot','watch'].includes(kind)?'pending':'confirm',now());
    await store.run('UPDATE messages SET task=? WHERE chat=? AND id=?',id,m.chat.id,m.message_id);
    if(['gitpull','python'].includes(kind)) return confirm(env,store,m.chat.id,project,id,'pc');
    return reply(`İstek PC kuyruğuna alındı: ${id}. Bilgisayar kapalıysa açılmasını bekler; henüz görüntü veya sonuç alınmadı.`,id);
  }
  if(['/gorev','/eklenecek'].includes(command)||(!text.trim().startsWith('/')&&text.trim())) {
    const body=text.trim().startsWith('/')?text.trim().slice(raw.length).trim():text.trim();
    if(!body || body.length>3500) return reply('İstek 1–3500 karakter olmalı. /gorev açıklama');
    const count=await store.one('SELECT count(*) AS n FROM tasks WHERE project=?',project);
    if(count.n>=100) return reply('Bu projede 100 istek var. Gereksiz kayıtları temizle.');
    const id=`t${update.update_id}`;
    if(command!=='/eklenecek') {
      if(!env.PC_SECRET) return reply('Yerel PC bağlantısı henüz kurulmadı.');
      const jobs=await store.one("SELECT count(*) n FROM pc_jobs WHERE project=? AND state!='done'",project);
      if(jobs.n>=50) return reply('PC kuyruğu dolu. Önce bekleyen işleri temizle.');
      await store.run('INSERT OR IGNORE INTO pc_jobs(id,project,kind,payload,state,created) VALUES(?,?,?,?,?,?)',id,project,'codex',JSON.stringify({prompt:body}),'pending',now());
    }
    await store.run('INSERT OR IGNORE INTO tasks VALUES(?,?,?,?)',id,project,body,now());
    await store.run('UPDATE messages SET task=? WHERE chat=? AND id=?',id,m.chat.id,m.message_id);
    return reply(`İstek kaydedildi: ${id}\n${command==='/eklenecek'?'Yalnızca not olarak saklandı.':'Yerel Codex kuyruğuna alındı. Bilgisayar açıkken çalışır; henüz tamamlanmadı.'}`,id);
  }
  if(['/gorevler','/yapilacaklar'].includes(command)) {
    const rows=await store.all('SELECT id,created FROM tasks WHERE project=? ORDER BY created DESC LIMIT 15',project);
    // Do not duplicate sensitive task bodies into lists or deletion confirmations.
    return reply(rows.length?rows.map(r=>`${r.id} • ${new Date(r.created*1000).toISOString()}`).join('\n'):'Bu projede istek yok.');
  }
  if(command==='/sil') {
    const id=args[0]||'';
    const task=await store.one('SELECT id FROM tasks WHERE project=? AND id=?',project,id);
    const job=await store.one('SELECT id FROM pc_jobs WHERE project=? AND id=?',project,id);
    if(!task&&!job) return reply('Bu projede görev bulunamadı. /gorevler ile kimliği al.');
    return confirm(env,store,m.chat.id,project,id,'erase');
  }
  if(command==='/goster') {
    const task=await store.one('SELECT id,body FROM tasks WHERE project=? AND id=?',project,args[0]||'');
    return task?reply(task.body,task.id):reply('Bu projede görev bulunamadı.');
  }
  if(command==='/temizle') return confirm(env,store,m.chat.id,project,null,'erase');
  if(command==='/derleme_ayarla') {
    if(!/^[a-zA-Z0-9_-]+\.ya?ml$/.test(args[0]||'') || !/^[A-Za-z0-9_./-]{1,100}$/.test(args[1]||'') || args[1].includes('..')) return reply('Kullanım: /derleme_ayarla build.yml main');
    await store.run('UPDATE projects SET workflow=?,ref=? WHERE alias=?',args[0],args[1],project);
    return reply('Derleme bağlantısı kaydedildi. Workflow mevcut ve yalnızca derleme için hazırlanmış olmalı.');
  }
  if(command==='/derle') return confirm(env,store,m.chat.id,project,null,'build');
  return reply('Komut tanınmadı. /kilavuz ile komutları gör.');
}
async function equalSecret(a,b) {
  if(!a||!b) return false;
  const e=new TextEncoder();
  const hashes=await Promise.all([a,b].map(s=>crypto.subtle.digest('SHA-256',e.encode(s))));
  const x=new Uint8Array(hashes[0]),y=new Uint8Array(hashes[1]);
  let diff=0; for(let i=0;i<x.length;i++) diff|=x[i]^y[i];
  return diff===0;
}
function json(body,status=200) {return Response.json(body,{status});}
async function pcRequest(request,env,path) {
  if(!env.PC_SECRET||!env.DB||!env.BOT_TOKEN||!env.OWNER_ID) return json({error:'not_configured'},503);
  if(!await equalSecret(request.headers.get('Authorization'),`Bearer ${env.PC_SECRET}`)) return json({error:'forbidden'},403);
  const raw=await request.text();
  if(raw.length>900000) return json({error:'too_large'},413);
  let body;
  try {body=JSON.parse(raw);}catch{return json({error:'invalid_json'},400);}
  if(!body||!aliasOK(body.project||'')) return json({error:'invalid_project'},400);
  const store=db(env);
  if(!await store.one('SELECT alias FROM projects WHERE alias=?',body.project)) return json({error:'unknown_project'},404);
  if(path==='/pc/ping') {
    await store.run("INSERT INTO pc_status(project,seen) VALUES(?,?) ON CONFLICT(project) DO UPDATE SET seen=excluded.seen",body.project,now());
    if(body.error && typeof body.error==='string') {
      // Error text is stored only on an explicit configured local watcher report.
      const previous=await store.one('SELECT last_error FROM pc_status WHERE project=?',body.project);
      await store.run('UPDATE pc_status SET last_error=? WHERE project=?',body.error.slice(0,3500),body.project);
      if(previous?.last_error!==body.error.slice(0,3500)) await send(env,store,Number(env.OWNER_ID),body.project,'PC dosya takip raporu:\n'+body.error.slice(0,3500));
    }
    const job=await store.one("SELECT * FROM pc_jobs WHERE project=? AND (state='pending' OR (state='running' AND lease_until<?)) ORDER BY created LIMIT 1",body.project,now());
    if(!job) return json({job:null});
    const lease=crypto.randomUUID();
    const claimed=await store.run("UPDATE pc_jobs SET state='running',lease=?,lease_until=? WHERE id=? AND (state='pending' OR (state='running' AND lease_until<?))",lease,now()+600,job.id,now());
    if(claimed.meta.changes!==1) return json({job:null});
    return json({job:{id:job.id,kind:job.kind,payload:JSON.parse(job.payload),lease}});
  }
  if(path==='/pc/heartbeat') {
    const changed=await store.run("UPDATE pc_jobs SET lease_until=? WHERE id=? AND project=? AND lease=? AND state='running' AND lease_until>=?",now()+600,body.id||'',body.project,body.lease||'',now());
    if(changed.meta.changes!==1) return json({error:'invalid_lease'},409);
    await store.run('UPDATE pc_status SET seen=? WHERE project=?',now(),body.project);
    return json({accepted:true});
  }
  if(path!=='/pc/result') return json({error:'not_found'},404);
  const job=await store.one('SELECT * FROM pc_jobs WHERE id=? AND project=?',body.id||'',body.project);
  if(!job) return json({error:'job_removed'},404);
  if(job.state==='done'&&job.lease===body.lease) return json({accepted:true});
  if(job.state!=='running'||job.lease!==body.lease||job.lease_until<now()) return json({error:'invalid_lease'},409);
  if(typeof body.text!=='string'||body.text.length>3500|| (body.image && (typeof body.image!=='string'||body.image.length>800000))) return json({error:'invalid_result'},400);
  let image;
  if(body.image) {
    if(job.kind!=='screenshot') return json({error:'unexpected_image'},400);
    try {image=Uint8Array.from(atob(body.image),c=>c.charCodeAt(0));}catch{return json({error:'invalid_image'},400);}
    if(image[0]!==255||image[1]!==216||image.length>600000) return json({error:'invalid_image'},400);
  }
  const claimed=await store.run("UPDATE pc_jobs SET state='delivering' WHERE id=? AND state='running' AND lease=?",job.id,body.lease);
  if(claimed.meta.changes!==1) return json({error:'busy'},409);
  try {
    if(image) {
      const form=new FormData();
      form.set('chat_id',String(env.OWNER_ID));form.set('protect_content','true');
      form.set('caption','İstediğin PC ekran görüntüsü. Yakalama zamanı: '+String(body.captured_at||'belirtilmedi').slice(0,50));
      form.set('photo',new Blob([image],{type:'image/jpeg'}),'screen.jpg');
      const r=await fetch(`https://api.telegram.org/bot${env.BOT_TOKEN}/sendPhoto`,{method:'POST',body:form,signal:AbortSignal.timeout(12000)});
      const result=await r.json();if(!r.ok||!result.ok)throw new Error('Delivery failed');
      await track(store,Number(env.OWNER_ID),result.result.message_id,job.project,job.id);
    } else {
      await send(env,store,Number(env.OWNER_ID),job.project,`PC işlemi ${job.id}:\n${body.text}`,job.id);
    }
    await store.run("UPDATE pc_jobs SET state='done',payload='' WHERE id=? AND lease=?",job.id,body.lease);
    return json({accepted:true});
  }catch{
    await store.run("UPDATE pc_jobs SET state='running' WHERE id=? AND lease=?",job.id,body.lease);
    return json({error:'delivery_failed'},503);
  }
}
export default {
  async fetch(request,env) {
    const path=new URL(request.url).pathname;
    if(request.method==='GET' && path==='/') return new Response('Project assistant online.');
    if(request.method==='POST'&&['/pc/ping','/pc/result','/pc/heartbeat'].includes(path)) {
      try {return await pcRequest(request,env,path);}catch{return json({error:'retry'},503);}
    }
    if(path!=='/telegram' || request.method!=='POST') return new Response('Not found',{status:404});
    if(!env.BOT_TOKEN||!env.OWNER_ID||!env.WEBHOOK_SECRET||!env.DB) return new Response('Not configured',{status:503});
    if(!await equalSecret(request.headers.get('X-Telegram-Bot-Api-Secret-Token'),env.WEBHOOK_SECRET)) return new Response('Forbidden',{status:403});
    if(Number(request.headers.get('content-length'))>20000) return new Response('Too large',{status:413});
    let update;
    try {const text=await request.text();if(text.length>20000)return new Response('Too large',{status:413});update=JSON.parse(text);}
    catch {return new Response('Invalid JSON',{status:400});}
    if(!update || !Number.isSafeInteger(update.update_id)) return new Response('Invalid update',{status:400});
    const store=db(env);
    const claim=await store.run('INSERT OR IGNORE INTO updates VALUES(?,?)',update.update_id,now());
    if(claim.meta.changes===0) return new Response('OK');
    try {await processUpdate(env,update);}
    catch {await store.run('DELETE FROM updates WHERE id=?',update.update_id);return new Response('Retry',{status:503});}
    return new Response('OK');
  },
  async scheduled(_,env) {
    await env.DB.batch([
      env.DB.prepare('DELETE FROM updates WHERE created<?').bind(now()-7*86400),
      env.DB.prepare('DELETE FROM confirmations WHERE created<?').bind(now()-300),
      env.DB.prepare('DELETE FROM messages WHERE created<?').bind(now()-30*86400),
      env.DB.prepare("DELETE FROM pc_jobs WHERE state='done' AND created<?").bind(now()-7*86400),
      env.DB.prepare("DELETE FROM pc_jobs WHERE state='confirm' AND created<?").bind(now()-300),
      env.DB.prepare("UPDATE pc_jobs SET state='running' WHERE state='delivering' AND lease_until<?").bind(now()),
    ]);
  },
};
