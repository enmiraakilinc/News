import {streamReleaseAsset} from './release_asset.mjs';
const error = status => Response.json({message:'Geçiş güncellemesi şu anda kullanılamıyor.'},{status,headers:{'Cache-Control':'no-store'}});
// Only the already-public, explicitly approved transition APK may use this route.
const VERSION='1.14.32';
const DIGEST='4f562651e24c3066d6bf2b7f208f899297bae61f04e53aa200d0cb8a516a2c34';
export async function transitionUpdate(request,env,{fetch:fetcher=fetch,token}={}) {
  if(request.method!=='GET'||env.UPDATE_BOOTSTRAP_ENABLED!=='true') return error(404);
  if(!env.GITHUB_RELEASE_TOKEN) return error(503);
  try {
    const response=await fetcher(`https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents/config/transition_app_version`,{headers:{Authorization:`Bearer ${await token()}`}});
    if(!response.ok)return error(503);
    const f=(await response.json()).fields;
    if(f?.enabled?.booleanValue!==true||f.name?.stringValue!==VERSION||f.sha256?.stringValue!==DIGEST||f.repository?.stringValue!==env.GITHUB_RELEASE_REPO) return error(404);
    return streamReleaseAsset(env,fetcher,f.assetId?.integerValue,VERSION);
  }catch{return error(503);}
}
