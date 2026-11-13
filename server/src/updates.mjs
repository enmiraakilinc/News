// Yayınlanmış APK sürümlerini listeler ve seçilen sürüme geri alır.
import {createReadStream} from 'node:fs';
import {readFile,readdir,writeFile,stat} from 'node:fs/promises';
import path from 'node:path';
import {ApiError} from './access.mjs';
import {str,bool} from './service_store.mjs';

const versionName=/^\d+\.\d+\.\d+$/;
const digest=/^[a-f0-9]{64}$/;

export function releasesDirectory(){
 return process.env.NEURAL_RELEASES_DIR||'/var/lib/neural/releases';
}
async function readJson(file){
 try{return JSON.parse(await readFile(file,'utf8'));}catch{return null;}
}
function releaseOf(item){
 const code=Number(item?.code);
 if(!versionName.test(item?.name??'')||!digest.test(item?.sha256??'')||!Number.isSafeInteger(code))return null;
 return {name:item.name,code,sha256:item.sha256,notes:typeof item.notes==='string'?item.notes:''};
}
function fromConfig(config){
 return releaseOf({name:str(config,'name'),code:Number(config?.code?.integerValue),sha256:str(config,'sha256'),notes:str(config,'notes')??''});
}
export async function listReleases(store,directory=releasesDirectory()){
 const items=new Map();
 const catalog=await readJson(path.join(directory,'catalog.json'));
 if(Array.isArray(catalog))for(const item of catalog){const release=releaseOf(item);if(release)items.set(release.name,release);}
 const current=fromConfig(await store.get('config/private_app_version'));
 if(current)items.set(current.name,current);
 let names=[];
 try{names=(await readdir(directory)).filter(name=>/^\d+\.\d+\.\d+\.apk$/.test(name));}catch{}
 for(const file of names){
  const name=file.slice(0,-4);
  if(items.has(name))continue;
  const meta=releaseOf(await readJson(path.join(directory,name+'.json')));
  if(meta)items.set(name,meta);
 }
 const activeFile=await readJson(path.join(directory,'active.json'));
 const active=releaseOf(activeFile);
 return {active:active?.name||current?.name||null,rollback:activeFile?.rollback===true,releases:[...items.values()].sort((a,b)=>b.code-a.code)};
}
export async function activateRelease(store,name,directory=releasesDirectory()){
 if(!versionName.test(name))throw new ApiError(400,'invalid-argument','Sürüm adı geçersiz.');
 const listed=await listReleases(store,directory);
 const chosen=listed.releases.find(item=>item.name===name);
 if(!chosen)throw new ApiError(404,'not-found','Bu sürüm bulunamadı.');
 try{const file=await stat(path.join(directory,name+'.apk'));if(!file.isFile())throw new Error('missing');}
 catch{throw new ApiError(404,'not-found','APK dosyası yok.');}
 const active={...chosen,rollback:true};
 await writeFile(path.join(directory,'active.json'),JSON.stringify(active));
 await writeFile(path.join(directory,'catalog.json'),JSON.stringify(listed.releases));
 await writeFile(path.join(directory,name+'.json'),JSON.stringify(chosen));
 return active;
}
export async function privateUpdate(store,auth,url,response,{directory=releasesDirectory()}={}){
 if(!auth.uid)throw new ApiError(401,'unauthenticated','Güncelleme için giriş yap.');
 if(!bool(await store.get('updateAccess/'+auth.uid),'enabled'))throw new ApiError(403,'permission-denied','Bu hesabın güncelleme erişimi yok.');
 const activeFile=await readJson(path.join(directory,'active.json'));
 const active=releaseOf(activeFile);
 const chosen=active||fromConfig(await store.get('config/private_app_version'));
 if(!chosen)throw new ApiError(503,'unavailable','Güncelleme hazırlanıyor.');
 const rollback=activeFile?.rollback===true&&active?.name===chosen.name;
 let file;try{file=await stat(path.join(directory,chosen.name+'.apk'));}catch{throw new ApiError(503,'unavailable','Güncelleme dosyası hazırlanıyor.');}
 if(!file.isFile())throw new ApiError(503,'unavailable','Güncelleme dosyası hazırlanıyor.');
 const headers={'cache-control':'no-store','x-content-type-options':'nosniff'};
 if(url.pathname==='/updates/latest'){
  response.writeHead(200,{...headers,'content-type':'application/json; charset=utf-8'});
  const downloadUrl=new URL('/updates/apk',url);
  downloadUrl.searchParams.set('version',chosen.name);
  response.end(JSON.stringify({code:chosen.code,name:chosen.name,sha256:chosen.sha256,notes:chosen.notes,rollback,url:downloadUrl.toString()}));return;
 }
 if(url.searchParams.get('version')!==chosen.name)throw new ApiError(409,'failed-precondition','Daha yeni bir güncelleme var. Tekrar kontrol et.');
 response.writeHead(200,{...headers,'content-type':'application/vnd.android.package-archive','content-length':file.size,'content-disposition':'attachment; filename="Neural-Haber-'+chosen.name+'.apk"'});
 const stream=createReadStream(path.join(directory,chosen.name+'.apk'));
 response.once('close',()=>stream.destroy());stream.on('error',()=>response.destroy());stream.pipe(response);
}
