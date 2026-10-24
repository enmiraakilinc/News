export function timestamp(t) {
 const start=new Date(Number(t.seconds)*1000).toISOString().slice(0,19);
 const nanos=String(t.nanoseconds).padStart(9,'0');
 const fraction=nanos==='000000000'?'':'.'+(nanos.endsWith('000000')?nanos.slice(0,3):nanos.endsWith('000')?nanos.slice(0,6):nanos);
 return start+fraction+'Z';
}
export function encodeValue(v) {
 if(v===null)return {nullValue:null};
 if(typeof v==='bigint')return {integerValue:v.toString()};
 if(typeof v==='string')return {stringValue:v};
 if(typeof v==='boolean')return {booleanValue:v};
 if(typeof v==='number')return Number.isSafeInteger(v)?{integerValue:String(v)}:{doubleValue:Number.isFinite(v)?v:String(v)};
 if(v instanceof Uint8Array)return {bytesValue:Buffer.from(v).toString('base64')};
 if(Array.isArray(v))return {arrayValue:{values:v.map(encodeValue)}};
 if(typeof v?.seconds==='number'&&typeof v?.nanoseconds==='number')return {timestampValue:timestamp(v)};
 if(v instanceof Date)return {timestampValue:v.toISOString()};
 if(typeof v?.latitude==='number'&&typeof v?.longitude==='number')return {geoPointValue:{latitude:v.latitude,longitude:v.longitude}};
 if(typeof v?.path==='string'&&v.firestore)return {referenceValue:'projects/'+v.firestore.projectId+'/databases/(default)/documents/'+v.path};
 if(v&&typeof v==='object')return {mapValue:{fields:encodeFields(v)}};
 throw Error('unsupported_firestore_type');
}
export function encodeFields(v) {return Object.fromEntries(Object.entries(v).map(([k,val])=>[k,encodeValue(val)]));}
export function snapshotDocument(s,project) {
 return {name:'projects/'+project+'/databases/(default)/documents/'+s.ref.path,
  fields:encodeFields(s.data()),createTime:timestamp(s.createTime),updateTime:timestamp(s.updateTime)};
}
