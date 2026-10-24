"""Import a verified snapshot into an isolated PostgreSQL database; verify every document."""
import gzip,hashlib,json,pathlib,subprocess,os
def import_snapshot(options):
    os.umask(0o077)
    target=pathlib.Path(options["snapshot"]).resolve()
    root=(pathlib.Path.home()/".local/share/neural-backups").resolve()
    assert target.is_relative_to(root) and target.suffix==".gz"
    schema=options["schema"]
    def sql(query,db="postgres"):
        return subprocess.check_output(["sudo","-n","-u","postgres","psql","-XqAt","-d",db,"--set","ON_ERROR_STOP=1","-c",query],stderr=subprocess.DEVNULL,text=True)
    if sql("SELECT 1 FROM pg_database WHERE datname='neural_haber';").strip()!="1":
        subprocess.run(["sudo","-n","-u","postgres","createdb","neural_haber"],check=True,stderr=subprocess.DEVNULL)
    sql(schema,"neural_haber")
    if int(sql("SELECT count(*) FROM neural.documents;","neural_haber").strip())!=0:
        raise RuntimeError("Target already contains records; review before replacing any data.")
    log=root/"postgres-import-errors.log"
    expected={}
    total=hashlib.sha256()
    with log.open("wb") as errors:
        process=subprocess.Popen(["sudo","-n","-u","postgres","psql","-Xq","-d","neural_haber","--set","ON_ERROR_STOP=1"],
            stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=errors)
        try:
            process.stdin.write(b"CREATE TEMP TABLE imported(doc jsonb);\nCOPY imported(doc) FROM STDIN WITH (FORMAT csv, DELIMITER E'\\x01', QUOTE E'\\x02');\n")
            with gzip.open(target,"rb") as stream:
                for line in stream:
                    total.update(line)
                    doc=json.loads(line)
                    path=doc["name"].partition("/documents/")[2]
                    expected[path]=hashlib.sha256(line.rstrip(b"\n")).hexdigest()
                    process.stdin.write(line)
            if total.hexdigest()!=options["sha256"]:
                raise RuntimeError("Snapshot hash mismatch; no data imported.")
            process.stdin.write(b"\\.\n")
            statement="""
BEGIN;
INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document)
SELECT path,regexp_replace(path,'/[^/]+$',''),split_part(path,'/',cardinality(string_to_array(path,'/'))-1),
split_part(path,'/',cardinality(string_to_array(path,'/'))),doc
FROM (SELECT substring(doc->>'name' FROM position('/documents/' IN doc->>'name')+11) AS path,doc FROM imported) x;
COMMIT;
"""
            process.stdin.write(statement.encode());process.stdin.close()
            if process.wait(timeout=600)!=0:raise RuntimeError("PostgreSQL import failed; see protected server log.")
        except BaseException:
            process.kill();process.wait()
            raise
    actual={}
    process=subprocess.Popen(["sudo","-n","-u","postgres","psql","-XqAt","-d","neural_haber","-c","SELECT document::text FROM neural.documents ORDER BY path;"],
        stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
    for line in process.stdout:
        doc=json.loads(line)
        path=doc["name"].partition("/documents/")[2]
        canonical=json.dumps(doc,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
        actual[path]=hashlib.sha256(canonical).hexdigest()
    if process.wait()!=0 or expected!=actual:raise RuntimeError("PostgreSQL document verification failed.")
    sql("INSERT INTO neural.migration_runs(read_time,document_count,canonical_sha256) VALUES ('"+
        options["readTime"]+"',"+str(len(actual))+",'"+options["sha256"]+"');","neural_haber")
    result={"documents":len(actual),"everyDocumentHashVerified":True,
        "databaseBytes":int(sql("SELECT pg_database_size('neural_haber');").strip()),
        "snapshotReadTime":options["readTime"],"firebaseModified":False,"applicationCutover":False}
    (root/"postgres-import-report.json").write_text(json.dumps(result,indent=2))
    print(json.dumps(result),flush=True)
