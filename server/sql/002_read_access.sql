DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='neural_api') THEN
  CREATE ROLE neural_api LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='neural_sync') THEN
  CREATE ROLE neural_sync LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
 END IF;
END $$;
CREATE OR REPLACE FUNCTION neural.raw_document(p text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT document FROM neural.documents WHERE path=p $$;
REVOKE ALL ON FUNCTION neural.raw_document(text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION neural.member(kind text,id text,uid text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT COALESCE(neural.raw_document(kind||'/'||id) #> '{fields,members,arrayValue,values}'
 @> jsonb_build_array(jsonb_build_object('stringValue',uid)),false) $$;
REVOKE ALL ON FUNCTION neural.member(text,text,text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION neural.media_member(d jsonb,uid text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT neural.member('chats',d #>> '{fields,chatId,stringValue}',uid)
 OR neural.member('couples',d #>> '{fields,coupleId,stringValue}',uid) $$;
REVOKE ALL ON FUNCTION neural.media_member(jsonb,text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION neural.call_participant(d jsonb,uid text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$ SELECT COALESCE(
 d #>> '{fields,sourceType,stringValue}' IN ('chat','couple')
 AND d #>> '{fields,sourceKey,stringValue}'=(d #>> '{fields,sourceType,stringValue}')||'/'||(d #>> '{fields,sourceId,stringValue}')
 AND uid IN (d #>> '{fields,caller,stringValue}',d #>> '{fields,callee,stringValue}')
 AND jsonb_array_length(neural.raw_document(
  (CASE d #>> '{fields,sourceType,stringValue}' WHEN 'chat' THEN 'chats' ELSE 'couples' END)
  ||'/'||(d #>> '{fields,sourceId,stringValue}')) #> '{fields,members,arrayValue,values}')=2
 AND neural.member(CASE d #>> '{fields,sourceType,stringValue}' WHEN 'chat' THEN 'chats' ELSE 'couples' END,
  d #>> '{fields,sourceId,stringValue}',d #>> '{fields,caller,stringValue}')
 AND neural.member(CASE d #>> '{fields,sourceType,stringValue}' WHEN 'chat' THEN 'chats' ELSE 'couples' END,
  d #>> '{fields,sourceId,stringValue}',d #>> '{fields,callee,stringValue}'),false) $$;
REVOKE ALL ON FUNCTION neural.call_participant(jsonb,text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION neural.chat_media_expiry(d jsonb) RETURNS timestamptz
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT COALESCE((d #>> '{fields,expiresAt,timestampValue}')::timestamptz,
   (d #>> '{fields,createdAt,timestampValue}')::timestamptz+interval '2 days')
$$;
REVOKE ALL ON FUNCTION neural.chat_media_expiry(jsonb) FROM PUBLIC;
CREATE OR REPLACE FUNCTION neural.share_conversation(a text,b text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT a IS NOT NULL AND b IS NOT NULL AND a<>'' AND b<>'' AND (a=b OR EXISTS(
  SELECT 1 FROM neural.documents WHERE collection_id IN ('chats','couples') AND parent_path=collection_id
   AND document @> jsonb_build_object('fields',jsonb_build_object('members',jsonb_build_object('arrayValue',
     jsonb_build_object('values',jsonb_build_array(jsonb_build_object('stringValue',a),jsonb_build_object('stringValue',b))))))
 ))
$$;
REVOKE ALL ON FUNCTION neural.share_conversation(text,text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION neural.can_read(p text,d jsonb,uid text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE parts text[]:=string_to_array(p,'/'); n integer:=cardinality(parts); media jsonb;
BEGIN
 IF n=2 AND parts[1]='config' AND parts[2] IN ('app_version','wakeup','voice_calls') THEN RETURN true; END IF;
 IF uid IS NULL OR uid='' THEN RETURN false; END IF;
 IF parts[1]='couples' THEN
  IF n=8 AND parts[3]='courses' AND parts[5]='entries' AND parts[7]='chunks' THEN
   RETURN neural.member('couples',parts[2],uid) AND now()<
    (neural.raw_document(array_to_string(parts[1:6],'/')) #>> '{fields,createdAt,timestampValue}')::timestamptz+interval '7 days';
  END IF;
  RETURN neural.member('couples',parts[2],uid);
 END IF;
 IF parts[1]='chats' THEN RETURN (n=2 OR (n=4 AND parts[3]='messages')) AND neural.member('chats',parts[2],uid); END IF;
 IF n=4 AND parts[1]='chatAccounts' AND parts[3]='presence' AND parts[4]='status' THEN RETURN parts[2]=uid OR neural.share_conversation(parts[2],uid) AND COALESCE(neural.raw_document('chatAccounts/'||parts[2]||'/personalConfig/presence') #> '{fields,peers,arrayValue,values}' @> jsonb_build_array(jsonb_build_object('stringValue',uid)),false); END IF;
 IF parts[1]='chatAccounts' THEN
  IF parts[2]<>uid THEN RETURN false; END IF;
  IF n=6 AND parts[3]='personalFiles' AND parts[5]='chunks' THEN
   media:=neural.raw_document(array_to_string(parts[1:4],'/'));
   RETURN media #>> '{fields,ready,booleanValue}'='true' AND
    (media #>> '{fields,expiresAt,timestampValue}' IS NULL OR now()<(media #>> '{fields,expiresAt,timestampValue}')::timestamptz);
  END IF;
  RETURN n=4 AND parts[3] IN ('contacts','starredMessages','callDevices','wakeDevices','wakePermissions','personalData','personalFiles','personalConfig');
 END IF;
 IF n=2 AND parts[1] IN ('invites','chatInvites','chatProfiles') THEN RETURN true; END IF;
 IF n=4 AND parts[3]='names' AND parts[1] IN ('chatContactLabels','coupleContactLabels') THEN
  RETURN neural.member(CASE parts[1] WHEN 'chatContactLabels' THEN 'chats' ELSE 'couples' END,parts[2],uid);
 END IF;
 IF parts[1]='voiceCalls' THEN
  IF n=2 THEN RETURN neural.call_participant(d,uid); END IF;
  RETURN n=4 AND parts[3]='candidates' AND neural.call_participant(neural.raw_document('voiceCalls/'||parts[2]),uid);
 END IF;
 IF parts[1]='chatMedia' THEN
  IF n=2 THEN RETURN (d #>> '{fields,owner,stringValue}')=uid OR neural.media_member(d,uid); END IF;
  IF n<>4 OR parts[3] NOT IN ('chunks','preview') THEN RETURN false; END IF;
  media:=neural.raw_document('chatMedia/'||parts[2]);
  RETURN neural.media_member(media,uid) AND media #>> '{fields,ready,booleanValue}'='true'
   AND now() < neural.chat_media_expiry(media);
 END IF;
 IF n=2 AND parts[1]='sharedLocations' THEN RETURN neural.media_member(d,uid) AND now()<(d #>> '{fields,createdAt,timestampValue}')::timestamptz+interval '1 hour'; END IF;
 IF n=2 AND parts[1]='mediaDownloadRequests' THEN RETURN uid IN (d #>> '{fields,ownerUid,stringValue}',d #>> '{fields,requesterUid,stringValue}'); END IF;
 IF n=2 AND parts[1]='accountCodeAliases' THEN RETURN d #>> '{fields,owner,stringValue}'=uid; END IF;
 IF n=2 AND parts[1]='accountLoginCodes' THEN RETURN parts[2]=uid; END IF;
 RETURN false;
END $$;
REVOKE ALL ON FUNCTION neural.can_read(text,jsonb,text) FROM PUBLIC;
GRANT USAGE ON SCHEMA neural TO neural_api,neural_sync;
GRANT SELECT ON neural.documents TO neural_api;
GRANT EXECUTE ON FUNCTION neural.can_read(text,jsonb,text) TO neural_api;
DROP POLICY IF EXISTS client_reads ON neural.documents;
CREATE POLICY client_reads ON neural.documents FOR SELECT TO neural_api
 USING(neural.can_read(path,document,current_setting('neural.uid',true)));
GRANT SELECT,INSERT,UPDATE,DELETE ON neural.documents TO neural_sync;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA neural TO neural_sync;
DROP POLICY IF EXISTS mirror_writes ON neural.documents;
CREATE POLICY mirror_writes ON neural.documents TO neural_sync USING(true) WITH CHECK(true);
CREATE OR REPLACE FUNCTION neural.document_changed() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
 PERFORM pg_notify('neural_changes',COALESCE(NEW.path,OLD.path)); RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS document_changed ON neural.documents;
CREATE TRIGGER document_changed AFTER INSERT OR UPDATE OR DELETE ON neural.documents
 FOR EACH ROW EXECUTE FUNCTION neural.document_changed();
CREATE TABLE IF NOT EXISTS neural.sync_state(
 collection_id text PRIMARY KEY,ready boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now(),error_code text
);
REVOKE ALL ON neural.sync_state FROM PUBLIC;
GRANT SELECT ON neural.sync_state TO neural_api;
GRANT SELECT,INSERT,UPDATE ON neural.sync_state TO neural_sync;
