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
