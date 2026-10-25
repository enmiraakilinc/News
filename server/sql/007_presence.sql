-- One optional timestamp per account; only current conversation peers may read.
CREATE INDEX IF NOT EXISTS documents_members_gin ON neural.documents USING gin(document jsonb_path_ops) WHERE collection_id IN ('chats','couples');
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
