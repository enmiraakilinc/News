export class ApiError extends Error {
 constructor(status,code,message) {super(message);this.status=status;this.code=code;}
}
export function docPath(p) {
 if(typeof p!=='string'||p.length>1500||p.includes('//')||p.startsWith('/')||p.endsWith('/')
  ||p.split('/').length%2!==0||p.split('/').some(s=>!s||s==='.'||s==='..'||/[\\\u0000-\u001f]/u.test(s))) {
  throw new ApiError(400,'invalid-argument','Geçersiz kayıt yolu.');
 }
 return p;
}
export function collectionPath(p) {
 if(typeof p!=='string'||p.length>1400||p.split('/').length%2!==1)throw new ApiError(400,'invalid-argument','Geçersiz liste yolu.');
 docPath(p+'/validation');return p;
}
export function queryAllowed(q,uid) {
 const p=collectionPath(q.path).split('/');
 const root=p.length===1?p[0]:null;
 const eq=(field,value,op='==')=>(q.filters??[]).some(f=>JSON.stringify(f.field)===JSON.stringify([field])&&f.op===op&&f.value?.stringValue===value);
 const okay=
  root==='chats'&&eq('members',uid,'array-contains') ||
  root==='voiceCalls'&&eq('callee',uid) ||
  root==='chatMedia'&&['owner','chatId','coupleId'].some(k=>(q.filters??[]).some(f=>JSON.stringify(f.field)===JSON.stringify([k])&&f.op==='=='&&typeof f.value?.stringValue==='string')) ||
  root==='mediaDownloadRequests'&&(eq('ownerUid',uid)||eq('requesterUid',uid)) ||
  p[0]==='couples'&&p.length>=3 ||
  p[0]==='chats'&&p.length===3&&p[2]==='messages' ||
  p[0]==='chatAccounts'&&p.length===3&&p[1]===uid&&['contacts','starredMessages','callDevices','wakeDevices','wakePermissions'].includes(p[2]) ||
  ['chatContactLabels','coupleContactLabels'].includes(p[0])&&p.length===3&&p[2]==='names' ||
  p[0]==='voiceCalls'&&p.length===3&&p[2]==='candidates';
 if(!uid||!okay)throw new ApiError(403,'permission-denied','Bu listeye erişim iznin yok.');
 if(q.limit!==undefined&&(!Number.isInteger(q.limit)||q.limit<1||q.limit>500))throw new ApiError(400,'invalid-argument','Liste boyutu geçersiz.');
 if((q.filters?.length??0)>12||(q.orders?.length??0)>8)throw new ApiError(400,'invalid-argument','Çok fazla filtre.');
}
export function validateCommit(body,project) {
 if(!Array.isArray(body.writes)||!body.writes.length||body.writes.length>500)throw new ApiError(400,'invalid-argument','Geçersiz işlem.');
 const prefix='projects/'+project+'/databases/(default)/documents/';
 for(const w of body.writes) {
  const name=w.update?.name??w.delete??w.transform?.document;
  if(typeof name!=='string'||!name.startsWith(prefix))throw new ApiError(400,'invalid-argument','Kayıt projesi geçersiz.');
  docPath(name.slice(prefix.length));
  if(Object.keys(w).some(k=>!['update','delete','transform','updateMask','updateTransforms','currentDocument'].includes(k)))throw new ApiError(400,'invalid-argument','İşlem biçimi geçersiz.');
 }
}
