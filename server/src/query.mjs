import {ApiError,queryAllowed} from './access.mjs';
export function compileQuery(q,uid,{count=false}={}) {
 queryAllowed(q,uid);
 const values=[q.path],bind=x=>{values.push(x);return '$'+values.length;};
 const expr=parts=>{
  if(!Array.isArray(parts)||!parts.length||parts.length>20||parts.some(p=>typeof p!=='string'||!p||p.length>1500))throw new ApiError(400,'invalid-argument','Alan adı geçersiz.');
  if(JSON.stringify(parts)==='["__name__"]')return 'to_jsonb(path)';
  const p=['fields',...parts.flatMap((s,i)=>i===parts.length-1?[s]:[s,'mapValue','fields'])];
  return 'COALESCE(to_jsonb(extract(epoch FROM (document #>> '+bind([...p,'timestampValue'])+'::text[])::timestamptz)),document #> '+bind([...p,'stringValue'])+'::text[],to_jsonb((document #>> '+bind([...p,'integerValue'])+'::text[])::numeric),document #> '+bind([...p,'doubleValue'])+'::text[],document #> '+bind([...p,'booleanValue'])+'::text[],document #> '+bind([...p,'nullValue'])+'::text[])';
 };
 const scalar=v=>{
  if('referenceValue' in (v??{}))return v.referenceValue.split('/documents/')[1];
  if('integerValue' in (v??{})) {
   // Avoid rounding int64 through JavaScript; numeric parameter is constructed
   // as JSON text directly after validating its decimal grammar.
   if(!/^-?\d+$/.test(String(v.integerValue)))throw new ApiError(400,'invalid-argument','Geçersiz sayı.');
   return {integerText:String(v.integerValue)};
  }
  for(const key of ['timestampValue','stringValue','doubleValue','booleanValue','nullValue'])if(key in (v??{}))return v[key];
  throw new ApiError(400,'invalid-argument','Bu filtre değeri desteklenmiyor.');
 };
 const literal=v=>{
  if(v?.timestampValue!==undefined)return 'to_jsonb(extract(epoch FROM '+bind(v.timestampValue)+'::timestamptz))';
  const s=scalar(v);return bind(s?.integerText??JSON.stringify(s))+'::jsonb';
 };
 const where=['parent_path=$1'];
 for(const f of q.filters??[]) {
  if(f.op==='array-contains'||f.op==='array-contains-any') {
   if(!Array.isArray(f.field)||!f.field.length)throw new ApiError(400,'invalid-argument','Geçersiz alan.');
   const p=['fields',...f.field.flatMap((s,i)=>i===f.field.length-1?[s]:[s,'mapValue','fields']),'arrayValue','values'];
   const vals=f.op==='array-contains'?[f.value]:f.value?.arrayValue?.values;
   if(!Array.isArray(vals)||!vals.length||vals.length>30)throw new ApiError(400,'invalid-argument','Geçersiz filtre.');
   where.push('('+vals.map(v=>'(document #> '+bind(p)+'::text[]) @> '+bind(JSON.stringify([v]))+'::jsonb').join(' OR ')+')');continue;
  }
  const x=expr(f.field);
  if(['in','not-in'].includes(f.op)) {
   const list=f.value?.arrayValue?.values;
   if(!Array.isArray(list)||!list.length||list.length>30)throw new ApiError(400,'invalid-argument','Geçersiz filtre listesi.');
   where.push((f.op==='not-in'?'NOT ':'')+'('+list.map(v=>x+' = '+literal(v)).join(' OR ')+')');continue;
  }
  const op={'==':'=','!=':'<>','<':'<','<=':'<=','>':'>','>=':'>='}[f.op];
  if(!op)throw new ApiError(400,'invalid-argument','Geçersiz karşılaştırma.');
  where.push(x+' '+op+' '+literal(f.value));
 }
 const orders=(q.orders??[]).map(o=>({sql:expr(o.field),descending:!!o.descending}));
 if(!orders.some(o=>o.sql==='to_jsonb(path)'))orders.push({sql:'to_jsonb(path)',descending:orders.at(-1)?.descending??false});
 for(const o of orders)where.push(o.sql+' IS NOT NULL');
 for(const [name,isEnd,inclusive] of [['startAt',false,true],['startAfter',false,false],['endAt',true,true],['endBefore',true,false]]) {
  if(!q[name])continue;
  const v=q[name];if(!Array.isArray(v)||!v.length||v.length>orders.length)throw new ApiError(400,'invalid-argument','Sayfa bilgisi geçersiz.');
  where.push('('+v.map((value,i)=>{
   const equal=orders.slice(0,i).map((o,j)=>o.sql+' = '+literal(v[j]));
   const greater=orders[i].descending===isEnd;
   return '('+[...equal,orders[i].sql+' '+(greater?'>':'<')+(inclusive&&i===v.length-1?'=':'')+' '+literal(value)].join(' AND ')+')';
  }).join(' OR ')+')');
 }
 const reverse=!!q.limitToLast;
 const order=' ORDER BY '+orders.map(o=>o.sql+((o.descending!==reverse)?' DESC':' ASC')).join(',');
 const limit=q.limit===undefined?'':' LIMIT '+bind(q.limit);
 const base='SELECT path,document,revision::text AS version FROM neural.documents WHERE '+where.join(' AND ')+order+limit;
 return {text:count?'SELECT count(*)::int AS count FROM ('+base+') AS matched':base,values};
}
