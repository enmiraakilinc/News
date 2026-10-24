import {getAuth} from 'firebase-admin/auth';
import {ApiError} from './access.mjs';
export async function authenticate(request) {
 const header=request.headers.authorization;
 if(!header)return {uid:'',token:'',expires:Date.now()+300000};
 if(!/^Bearer [A-Za-z0-9_.-]{50,8192}$/.test(header))throw new ApiError(401,'unauthenticated','Oturumunu yeniden açman gerekiyor.');
 const token=header.slice(7);
 try {
  const claims=await getAuth().verifyIdToken(token);
  return {uid:claims.uid,token,expires:claims.exp*1000};
 }catch{throw new ApiError(401,'unauthenticated','Oturumun doğrulanamadı. Yeniden giriş yap.');}
}
