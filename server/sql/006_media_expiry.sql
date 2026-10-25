-- Sender-controlled expiry; old documents keep the two-day default.
CREATE OR REPLACE FUNCTION neural.chat_media_expiry(d jsonb) RETURNS timestamptz
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT COALESCE((d #>> '{fields,expiresAt,timestampValue}')::timestamptz,
   (d #>> '{fields,createdAt,timestampValue}')::timestamptz+interval '2 days')
$$;
REVOKE ALL ON FUNCTION neural.chat_media_expiry(jsonb) FROM PUBLIC;
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
-- Run only after the explicitly controlled primary cutover.
-- Feature records (messages, memories, notes) are not deleted by media expiry.
CREATE OR REPLACE FUNCTION neural.prune_expired(batch_size integer DEFAULT 500)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE removed integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM neural.settings WHERE key='primary_writes' AND value='true'::jsonb)
 THEN RETURN 0; END IF;
 WITH expired_media AS MATERIALIZED (
  SELECT path FROM neural.documents
  WHERE collection_id='chatMedia' AND neural.chat_media_expiry(document)<=now()
  ORDER BY path LIMIT greatest(1,least(batch_size,2000))
  FOR UPDATE SKIP LOCKED
 ), expired AS (
 SELECT d.path FROM neural.documents d
 WHERE
  (split_part(d.path,'/',1)='chatMedia' AND
   ('chatMedia/'||split_part(d.path,'/',2) IN (SELECT path FROM expired_media)
    OR NOT EXISTS(SELECT 1 FROM neural.documents parent WHERE parent.path='chatMedia/'||split_part(d.path,'/',2))
      AND d.changed_at+interval '2 days'<=now()))
  OR (d.collection_id='sharedLocations' AND
   COALESCE((d.document #>> '{fields,createdAt,timestampValue}')::timestamptz,d.changed_at)<now()-interval '1 hour')
  OR (d.path ~ '^couples/[^/]+/courses/[^/]+/entries/[^/]+/chunks/[^/]+$' AND
   COALESCE((neural.raw_document(regexp_replace(d.path,'/chunks/[^/]+$','')) #>> '{fields,createdAt,timestampValue}')::timestamptz,
    d.changed_at)<now()-interval '7 days')
  OR (d.path ~ '^chatAccounts/[^/]+/personalFiles/[^/]+(/chunks/[^/]+)?$' AND
   (neural.raw_document(array_to_string((string_to_array(d.path,'/'))[1:4],'/')) #>> '{fields,expiresAt,timestampValue}')::timestamptz<now())
 ORDER BY d.path DESC LIMIT greatest(1,least(batch_size,2000))
 ), removed_rows AS (
 DELETE FROM neural.documents d USING expired e WHERE d.path=e.path RETURNING d.path
 )
 SELECT count(*)::integer INTO removed FROM removed_rows;
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION neural.prune_expired(integer) FROM PUBLIC;
