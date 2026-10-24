"""Read-only point-in-time Firestore snapshot. Never prints document contents."""
import concurrent.futures
import datetime
import gzip
import hashlib
import json
import os
import pathlib
import time
import urllib.request
import urllib.parse
import urllib.error

def snapshot(options):
    os.umask(0o077)
    project = options["project"]
    token = options["token"]
    started = datetime.datetime.now(datetime.timezone.utc)
    read_time = (started-datetime.timedelta(seconds=10)).isoformat(timespec="microseconds").replace("+00:00","Z")
    root = pathlib.Path.home()/".local/share/neural-backups"
    root.mkdir(parents=True,exist_ok=True,mode=0o700)
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    target = root/("firestore-"+stamp+".jsonl.gz")
    temporary = target.with_suffix(".part")
    base = "https://firestore.googleapis.com/v1/projects/"+project+"/databases/(default)/documents"

    def request(url, body=None):
        for attempt in range(5):
            try:
                data = json.dumps(body).encode() if body is not None else None
                req = urllib.request.Request(url,data=data,headers={
                    "Authorization":"Bearer "+token,"Content-Type":"application/json"})
                with urllib.request.urlopen(req,timeout=60) as r:
                    return json.load(r)
            except urllib.error.HTTPError as e:
                if e.code not in (429,500,502,503,504) or attempt==4:
                    raise RuntimeError("Firestore export HTTP "+str(e.code)) from None
                time.sleep(2**attempt)

    def collections(parent):
        result=[];page=None
        while True:
            body={"pageSize":1000,"readTime":read_time}
            if page:body["pageToken"]=page
            response=request(parent+":listCollectionIds",body)
            result.extend(parent+"/"+c for c in response.get("collectionIds",[]))
            page=response.get("nextPageToken")
            if not page:return result

    def documents(collection):
        result=[];page=None
        while True:
            query={"pageSize":50,"showMissing":"true","readTime":read_time}
            if page:query["pageToken"]=page
            response=request(collection+"?"+urllib.parse.urlencode(query))
            result.extend(response.get("documents",[]))
            page=response.get("nextPageToken")
            if not page:return result

    digest=hashlib.sha256()
    count=0;raw_bytes=0;groups={};parents=[base]
    with gzip.open(temporary,"wb",compresslevel=3) as out, concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        while parents:
            collection_paths=[]
            for values in executor.map(collections,parents):collection_paths.extend(values)
            parents=[]
            for values in executor.map(documents,collection_paths):
                for doc in values:
                    parents.append("https://firestore.googleapis.com/v1/"+doc["name"])
                    if "updateTime" not in doc:continue
                    line=json.dumps(doc,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()+b"\n"
                    out.write(line);digest.update(line);raw_bytes+=len(line);count+=1
                    collection=doc["name"].split("/")[-2]
                    groups[collection]=groups.get(collection,0)+1
                    if count>45000:raise RuntimeError("Snapshot safety limit reached; no source data changed.")
            print(json.dumps({"exportedDocuments":count,"rawBytes":raw_bytes,"remainingParents":len(parents)}),flush=True)
    temporary.rename(target)
    report={"project":project,"readTime":read_time,"documents":count,"rawBytes":raw_bytes,
        "gzipBytes":target.stat().st_size,"sha256OfCanonicalJsonLines":digest.hexdigest(),
        "collections":groups,"snapshot":str(target),"sourceModified":False}
    target.with_suffix(".report.json").write_text(json.dumps(report,indent=2))
    print(json.dumps(report),flush=True)
