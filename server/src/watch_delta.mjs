// Large file chunk uploads must not re-run unrelated message/photo queries.
// ACL ancestors still invalidate dependent reads immediately.
export function affectsWatch(request,changed){
 if(typeof changed!=='string')return true;
 if(/^(couples|chats)\/[^/]+$/.test(changed))return true;
 const path=request.kind==='document'?request.path:request.query?.path;
 if(!path)return true;
 if(path===changed||path.startsWith(changed+'/'))return true;
 return request.kind==='query'&&changed.slice(0,changed.lastIndexOf('/'))===path;
}
export class WatchDelta {
  #previous;
  next(value) {
    const rows=value.rows;
    if(!Array.isArray(rows))return value;
    const current=rows.map(r=>({path:r.path,version:r.version}));
    if(!this.#previous){this.#previous=current;return value;}
    const previous=this.#previous;
    const known=new Map(previous.map(r=>[r.path,r.version]));
    const present=new Set(current.map(r=>r.path));
    const upserts=rows.filter(r=>known.get(r.path)!==r.version);
    const remove=previous.filter(r=>!present.has(r.path)).map(r=>r.path);
    const moved=previous.length!==current.length||previous.some((r,i)=>r.path!==current[i]?.path);
    this.#previous=current;
    if(!upserts.length&&!remove.length&&!moved)return null;
    return {patch:{upserts,remove,order:current.map(r=>r.path)}};
  }
}
