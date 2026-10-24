import {createReadStream} from 'node:fs';
import {stat} from 'node:fs/promises';
import {ApiError} from './access.mjs';
import {str,bool} from './service_store.mjs';
export async function privateUpdate(store,auth,url,response,{directory='/var/lib/neural/releases'}={}){
 if(!auth.uid)throw new ApiError(401,'unauthenticated','Güncelleme için giriş yap.');
 if(!bool(await store.get('updateAccess/'+auth.uid),'enabled'))throw new ApiError(403,'permission-denied','Bu hesabın güncelleme erişimi yok.');
 const config=await store.get('config/private_app_version');
 const name=str(config,'name'),sha256=str(config,'sha256'),code=Number(config?.code?.integerValue);
 if(!/^\d+\.\d+\.\d+$/.test(name??'')||!/^[a-f0-9]{64}$/.test(sha256??'')||!Number.isSafeInteger(code))throw new ApiError(503,'unavailable','Güncelleme hazırlanıyor.');
 let file;try{file=await stat(directory+'/'+name+'.apk');}catch{throw new ApiError(503,'unavailable','Güncelleme dosyası hazırlanıyor.');}
 if(!file.isFile())throw new ApiError(503,'unavailable','Güncelleme dosyası hazırlanıyor.');
 const headers={'cache-control':'no-store','x-content-type-options':'nosniff'};
 if(url.pathname==='/updates/latest'){
  response.writeHead(200,{...headers,'content-type':'application/json; charset=utf-8'});
  response.end(JSON.stringify({code,name,sha256,notes:str(config,'notes')??'',url:'https://138.2.185.151/updates/apk?version='+name}));return;
 }
 if(url.searchParams.get('version')!==name)throw new ApiError(409,'failed-precondition','Daha yeni bir güncelleme var. Tekrar kontrol et.');
 response.writeHead(200,{...headers,'content-type':'application/vnd.android.package-archive','content-length':file.size,'content-disposition':'attachment; filename="Neural-Haber-'+name+'.apk"'});
 const stream=createReadStream(directory+'/'+name+'.apk');
 response.once('close',()=>stream.destroy());stream.on('error',()=>response.destroy());stream.pipe(response);
}
