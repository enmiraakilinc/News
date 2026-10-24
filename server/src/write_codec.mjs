import {isDeepStrictEqual as equal} from 'node:util';
import {ApiError} from './access.mjs';
import {Instant} from './write_policy.mjs';

const invalid=()=>{throw new ApiError(400,'invalid-argument','Kayıt biçimi geçersiz.');};
const validKey=k=>typeof k==='string'&&k.length>0&&k.length<=1500&&!['__proto__','prototype','constructor'].includes(k)&&!k.includes('\0');
export function fieldPath(value){
 if(!Array.isArray(value)||!value.length||value.length>20||!value.every(validKey))invalid();
 return value;
}
export function decodeTyped(v,depth=0){
 if(depth>20||!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==1)invalid();
 const [type]=Object.keys(v),value=v[type];
 switch(type){
  case 'nullValue':if(value!==null)invalid();return null;
  case 'booleanValue':if(typeof value!=='boolean')invalid();return value;
  case 'stringValue':if(typeof value!=='string')invalid();return value;
  case 'integerValue':{
   if(typeof value!=='string'||!/^(-?(0|[1-9][0-9]*))$/.test(value))invalid();
   const n=BigInt(value);
   if(n< -9223372036854775808n||n>9223372036854775807n)invalid();
   return n>=BigInt(Number.MIN_SAFE_INTEGER)&&n<=BigInt(Number.MAX_SAFE_INTEGER)?Number(n):n;
  }
  case 'doubleValue':{
   const n=typeof value==='number'?value:
    value==='NaN'?NaN:value==='Infinity'?Infinity:value==='-Infinity'?-Infinity:undefined;
   if(n===undefined)invalid();return n;
  }
  case 'timestampValue':if(typeof value!=='string')invalid();return Instant.parse(value);
  case 'bytesValue':{
   if(typeof value!=='string'||! /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value))invalid();
   return Buffer.from(value,'base64');
  }
  case 'arrayValue':
   if(!value||Object.keys(value).some(k=>k!=='values')||value.values!==undefined&&!Array.isArray(value.values))invalid();
   return (value.values??[]).map(x=>decodeTyped(x,depth+1));
  case 'mapValue':return decodeFields(value?.fields??{},depth+1);
  case 'referenceValue':
   if(typeof value!=='string'||!/^projects\/[a-z0-9-]+\/databases\/\(default\)\/documents\/.+$/.test(value))invalid();
   return new Reference(value);
  case 'geoPointValue':
   if(!value||typeof value.latitude!=='number'||typeof value.longitude!=='number'
     ||!Number.isFinite(value.latitude)||!Number.isFinite(value.longitude)||Math.abs(value.latitude)>90||Math.abs(value.longitude)>180)invalid();
   return new Geo(value.latitude,value.longitude);
  default:invalid();
 }
}
class Reference{constructor(value){this.value=value;}}
class Geo{constructor(latitude,longitude){this.latitude=latitude;this.longitude=longitude;}}
export function decodeFields(fields,depth=0){
 if(!fields||typeof fields!=='object'||Array.isArray(fields)||Object.keys(fields).length>2000)invalid();
 return Object.fromEntries(Object.entries(fields).map(([k,v])=>{
  if(!validKey(k))invalid();return [k,decodeTyped(v,depth+1)];
 }));
}
export function encodeTyped(value){
 if(value===null)return {nullValue:null};
 if(value instanceof Instant){
  const seconds=value.nanos/1000000000n;
  const nanos=((value.nanos%1000000000n)+1000000000n)%1000000000n;
  const epoch=value.nanos<0&&nanos>0?seconds-1n:seconds;
  const iso=new Date(Number(epoch)*1000).toISOString().split('.')[0];
  return {timestampValue:iso+'.'+nanos.toString().padStart(9,'0')+'Z'};
 }
 if(Buffer.isBuffer(value))return {bytesValue:value.toString('base64')};
 if(value instanceof Reference)return {referenceValue:value.value};
 if(value instanceof Geo)return {geoPointValue:{latitude:value.latitude,longitude:value.longitude}};
 if(Array.isArray(value))return {arrayValue:{values:value.map(encodeTyped)}};
 switch(typeof value){
  case 'string':return {stringValue:value};
  case 'boolean':return {booleanValue:value};
  case 'bigint':return {integerValue:value.toString()};
  case 'number':
   if(Number.isSafeInteger(value))return {integerValue:String(value)};
   return {doubleValue:Number.isNaN(value)?'NaN':value===Infinity?'Infinity':value===-Infinity?'-Infinity':value};
  case 'object':return {mapValue:{fields:encodeFields(value)}};
  default:invalid();
 }
}
export const encodeFields=v=>Object.fromEntries(Object.entries(v).map(([k,x])=>[k,encodeTyped(x)]));
const deleted=Symbol('deleted');
function resolve(value,old,now,allowDelete,depth=0){
 if(depth>20)invalid();
 if(value&&Object.hasOwn(value,'transformValue')){
  if(Object.keys(value).length!==1)invalid();
  const t=value.transformValue;
  if(!t||typeof t!=='object'||Object.keys(t).some(k=>!['operation','value'].includes(k)))invalid();
  if(t.operation==='serverTimestamp')return now;
  if(t.operation==='delete'){if(!allowDelete)invalid();return deleted;}
  if(t.operation==='increment'){
   const step=decodeTyped(t.value);
   if(!['number','bigint'].includes(typeof step))invalid();
   const initial=['number','bigint'].includes(typeof old)?old:0;
   if(typeof step==='bigint'||typeof initial==='bigint'){
    if(typeof step==='number'&&!Number.isSafeInteger(step)||typeof initial==='number'&&!Number.isSafeInteger(initial))
     return Number(initial)+Number(step);
    const sum=BigInt(initial)+BigInt(step);
    return sum< -9223372036854775808n?-9223372036854775808n:sum>9223372036854775807n?9223372036854775807n:sum;
   }
   const result=initial+step;
   if(Number.isInteger(initial)&&Number.isInteger(step)&&!Number.isSafeInteger(result)){
    const sum=BigInt(initial)+BigInt(step);
    return sum< -9223372036854775808n?-9223372036854775808n:sum>9223372036854775807n?9223372036854775807n:sum;
   }
   return result;
  }
  if(t.operation==='arrayUnion'||t.operation==='arrayRemove'){
   const args=decodeTyped(t.value);
   if(!Array.isArray(args))invalid();
   const result=Array.isArray(old)?[...old]:[];
   if(t.operation==='arrayRemove')return result.filter(x=>!args.some(v=>equal(x,v)));
   for(const v of args)if(!result.some(x=>equal(x,v)))result.push(v);
   return result;
  }
  invalid();
 }
 if(value?.mapValue){
  const fields=value.mapValue.fields??{};
  if(Object.keys(value).length!==1||!fields||Object.keys(fields).length>2000||Object.keys(fields).some(k=>!validKey(k)))invalid();
  const output={};
  for(const [key,v] of Object.entries(fields)){
   const result=resolve(v,old?.[key],now,allowDelete,depth+1);
   if(result!==deleted)Object.defineProperty(output,key,{value:result,writable:true,enumerable:true,configurable:true});
  }
  return output;
 }
 return decodeTyped(value,depth);
}
const get=(data,path)=>path.reduce((v,k)=>v?.[k],data);
function put(data,path,value){
 let d=data;
 for(const k of path.slice(0,-1)){
  if(!d[k]||typeof d[k]!=='object'||Object.getPrototypeOf(d[k])!==Object.prototype)d[k]={};
  d=d[k];
 }
 if(value===deleted)delete d[path.at(-1)];else d[path.at(-1)]=value;
}
function rawGet(fields,path){
 let raw={mapValue:{fields}};
 for(const key of path)raw=raw?.mapValue?.fields?.[key];
 if(raw===undefined)invalid();
 return raw;
}
function leaves(fields,prefix=[]){
 const result=[];
 for(const [key,v] of Object.entries(fields)){
  if(!validKey(key))invalid();
  const path=[...prefix,key];
  if(v?.mapValue&&Object.keys(v.mapValue.fields??{}).length)result.push(...leaves(v.mapValue.fields,path));
  else result.push(path);
 }
 return result;
}
/** Applies SDK set/update/delete semantics to plain typed documents. */
export function applyWrite(old,operation,now){
 if(operation.type==='delete')return null;
 if(operation.type==='update'){
  if(!old)throw new ApiError(404,'not-found','Düzenlenecek kayıt bulunamadı.');
  if(!Array.isArray(operation.fields)||operation.fields.length>2000)invalid();
  const output=decodeFields(encodeFields(old));
  const paths=operation.fields.map(f=>fieldPath(f.field));
  for(let i=0;i<paths.length;i++)for(let j=0;j<i;j++){
   const a=paths[i],b=paths[j],length=Math.min(a.length,b.length);
   if(a.slice(0,length).every((x,k)=>b[k]===x))invalid();
  }
  for(const [i,field] of operation.fields.entries()){
   const path=paths[i];
   put(output,path,resolve(field.value,get(old,path),now,true));
  }
  return output;
 }
 if(operation.type!=='set'||!operation.fields||typeof operation.fields!=='object'||Array.isArray(operation.fields))invalid();
 if(operation.merge!==undefined&&typeof operation.merge!=='boolean')invalid();
 if(operation.mergeFields!==undefined&&!Array.isArray(operation.mergeFields))invalid();
 const merge=operation.merge===true||operation.mergeFields!==undefined;
 const output=merge&&old?decodeFields(encodeFields(old)):{};
 const paths=operation.mergeFields?.map(fieldPath)??(merge?leaves(operation.fields):Object.keys(operation.fields).map(k=>fieldPath([k])));
 for(const path of paths)put(output,path,resolve(rawGet(operation.fields,path),get(old,path),now,merge));
 return output;
}
