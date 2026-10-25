-- Prepared migration. This does not enable primary writes.
ALTER TABLE neural.documents ADD COLUMN IF NOT EXISTS origin text NOT NULL DEFAULT 'firebase'
 CHECK(origin IN ('firebase','postgres'));
CREATE TABLE IF NOT EXISTS neural.settings (
 key text PRIMARY KEY,value jsonb NOT NULL
);
INSERT INTO neural.settings(key,value) VALUES
 ('primary_writes','false'),('minimum_client_code','2081')
 ON CONFLICT DO NOTHING;
REVOKE ALL ON neural.settings FROM PUBLIC;
GRANT SELECT ON neural.settings TO neural_api;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='neural_writer') THEN
  CREATE ROLE neural_writer NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
 END IF;
END $$;
GRANT neural_writer TO neural_api;
GRANT USAGE ON SCHEMA neural TO neural_writer;
GRANT SELECT ON neural.settings TO neural_writer;
GRANT SELECT,INSERT,UPDATE,DELETE ON neural.documents TO neural_writer;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA neural TO neural_writer;
GRANT EXECUTE ON FUNCTION neural.can_read(text,jsonb,text) TO neural_writer;
CREATE TABLE IF NOT EXISTS neural.commit_receipts(
 uid text NOT NULL,request_id uuid NOT NULL,request_hash text NOT NULL,
 response jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(uid,request_id)
);
ALTER TABLE neural.commit_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON neural.commit_receipts FROM PUBLIC;
GRANT SELECT,INSERT ON neural.commit_receipts TO neural_writer;
DROP POLICY IF EXISTS own_receipts ON neural.commit_receipts;
CREATE POLICY own_receipts ON neural.commit_receipts TO neural_writer
 USING(uid=current_setting('neural.uid',true))
 WITH CHECK(uid=current_setting('neural.uid',true));

CREATE OR REPLACE FUNCTION neural.write_scope(p text,d jsonb,uid text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE a text[]:=string_to_array(p,'/'); n integer:=cardinality(a);
BEGIN
 IF uid IS NULL OR uid='' THEN RETURN false; END IF;
 IF a[1]='couples' THEN
  IF n=2 THEN RETURN neural.member('couples',a[2],uid) OR
    COALESCE(d #> '{fields,members,arrayValue,values}' @> jsonb_build_array(jsonb_build_object('stringValue',uid)),false); END IF;
  RETURN neural.member('couples',a[2],uid);
 END IF;
 IF a[1]='chats' THEN
  IF n=2 THEN RETURN neural.member('chats',a[2],uid) OR
    COALESCE(d #> '{fields,members,arrayValue,values}' @> jsonb_build_array(jsonb_build_object('stringValue',uid)),false); END IF;
  RETURN n=4 AND a[3]='messages' AND neural.member('chats',a[2],uid);
 END IF;
 IF a[1]='chatAccounts' THEN RETURN a[2]=uid AND (
  n=4 AND a[3] IN ('contacts','starredMessages','callDevices','wakeDevices','wakePermissions','personalData','personalFiles','personalConfig','presence')
  OR n=6 AND a[3]='personalFiles' AND a[5]='chunks'); END IF;
 IF a[1]='chatProfiles' AND n=2 THEN RETURN a[2]=uid; END IF;
 IF a[1]='invites' AND n=2 THEN RETURN true; END IF;
 IF a[1]='chatInvites' AND n=2 THEN RETURN true; END IF;
 IF a[1] IN ('chatContactLabels','coupleContactLabels') THEN RETURN n=4 AND a[3]='names' AND a[4]=uid
   AND neural.member(CASE a[1] WHEN 'chatContactLabels' THEN 'chats' ELSE 'couples' END,a[2],uid); END IF;
 IF a[1]='voiceCalls' THEN
  IF n=2 THEN RETURN uid IN(d #>> '{fields,caller,stringValue}',d #>> '{fields,callee,stringValue}'); END IF;
  RETURN n=4 AND a[3]='candidates' AND neural.call_participant(neural.raw_document('voiceCalls/'||a[2]),uid);
 END IF;
 IF a[1]='chatMedia' THEN
  IF n=2 THEN RETURN d #>> '{fields,owner,stringValue}'=uid OR neural.media_member(d,uid); END IF;
  RETURN n=4 AND a[3] IN ('chunks','preview') AND neural.media_member(neural.raw_document('chatMedia/'||a[2]),uid);
 END IF;
 IF a[1]='sharedLocations' AND n=2 THEN RETURN neural.media_member(d,uid); END IF;
 IF a[1]='mediaDownloadRequests' AND n=2 THEN
  RETURN uid IN(d #>> '{fields,ownerUid,stringValue}',d #>> '{fields,requesterUid,stringValue}');
 END IF;
 IF a[1]='accountCodeAliases' AND n=2 THEN RETURN d #>> '{fields,owner,stringValue}'=uid; END IF;
 IF a[1]='accountLoginCodes' AND n=2 THEN RETURN a[2]=uid; END IF;
 RETURN false;
END $$;
REVOKE ALL ON FUNCTION neural.write_scope(text,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION neural.write_scope(text,jsonb,text) TO neural_writer;
DROP POLICY IF EXISTS write_validation_reads ON neural.documents;
CREATE POLICY write_validation_reads ON neural.documents FOR SELECT TO neural_writer USING(true);
DROP POLICY IF EXISTS scoped_insert ON neural.documents;
CREATE POLICY scoped_insert ON neural.documents FOR INSERT TO neural_writer
 WITH CHECK(origin='postgres' AND neural.write_scope(path,document,current_setting('neural.uid',true)));
DROP POLICY IF EXISTS scoped_update ON neural.documents;
CREATE POLICY scoped_update ON neural.documents FOR UPDATE TO neural_writer
 USING(neural.write_scope(path,document,current_setting('neural.uid',true)))
 WITH CHECK(origin='postgres' AND neural.write_scope(path,document,current_setting('neural.uid',true)));
DROP POLICY IF EXISTS scoped_delete ON neural.documents;
CREATE POLICY scoped_delete ON neural.documents FOR DELETE TO neural_writer
 USING(neural.write_scope(path,document,current_setting('neural.uid',true)));

-- A running or accidentally restarted mirror cannot change primary rows.
GRANT SELECT ON neural.settings TO neural_sync;
CREATE OR REPLACE FUNCTION neural.guard_mirror() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF session_user='neural_sync' THEN
  IF EXISTS(SELECT 1 FROM neural.settings WHERE key='primary_writes' AND value='true'::jsonb)
   OR (TG_OP<>'INSERT' AND OLD.origin='postgres') THEN
   RAISE EXCEPTION 'mirror is read only after primary cutover' USING ERRCODE='42501';
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION neural.guard_mirror() FROM PUBLIC;
DROP TRIGGER IF EXISTS guard_mirror ON neural.documents;
CREATE TRIGGER guard_mirror BEFORE INSERT OR UPDATE OR DELETE ON neural.documents
 FOR EACH ROW EXECUTE FUNCTION neural.guard_mirror();
