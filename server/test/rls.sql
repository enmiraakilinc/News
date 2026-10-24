-- Transactional fixtures: no test documents survive this check.
BEGIN;
INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document)
SELECT p,regexp_replace(p,'/[^/]+$',''),split_part(p,'/',cardinality(string_to_array(p,'/'))-1),
 split_part(p,'/',cardinality(string_to_array(p,'/'))),jsonb_build_object('fields',f)
FROM (VALUES
 ('couples/__migration_rls_pair','{"members":{"arrayValue":{"values":[{"stringValue":"__migration_rls_owner"},{"stringValue":"__migration_rls_partner"}]}}}'::jsonb),
 ('couples/__migration_rls_pair/letters/a','{"cipher":{"stringValue":"encrypted-test"}}'),
 ('chats/__migration_rls_chat','{"members":{"arrayValue":{"values":[{"stringValue":"__migration_rls_owner"},{"stringValue":"__migration_rls_chat_only"}]}}}'),
 ('chats/__migration_rls_chat/messages/a','{"sender":{"stringValue":"__migration_rls_owner"},"text":{"stringValue":"test"}}'),
 ('chatAccounts/__migration_rls_owner/contacts/a','{"alias":{"stringValue":"test"}}'),
 ('accountCodeAliases/__migration_rls_code','{"owner":{"stringValue":"__migration_rls_owner"}}'),
 ('accountLoginCodes/__migration_rls_owner','{"code":{"stringValue":"123456789012"}}'),
 ('config/__migration_rls_private','{"value":{"stringValue":"private"}}'),
 ('chatMedia/__migration_rls_active',jsonb_build_object('owner',jsonb_build_object('stringValue','__migration_rls_owner'),'chatId',jsonb_build_object('stringValue','__migration_rls_chat'),'ready',jsonb_build_object('booleanValue',true),'createdAt',jsonb_build_object('timestampValue',now()::text))),
 ('chatMedia/__migration_rls_active/chunks/0','{"bytes":{"bytesValue":"AA=="}}'),
 ('chatMedia/__migration_rls_expired',jsonb_build_object('owner',jsonb_build_object('stringValue','__migration_rls_owner'),'chatId',jsonb_build_object('stringValue','__migration_rls_chat'),'ready',jsonb_build_object('booleanValue',true),'createdAt',jsonb_build_object('timestampValue',(now()-interval '3 days')::text))),
 ('chatMedia/__migration_rls_expired/chunks/0','{"bytes":{"bytesValue":"AA=="}}'),
 ('voiceCalls/__migration_rls_call','{"caller":{"stringValue":"__migration_rls_owner"},"callee":{"stringValue":"__migration_rls_partner"},"sourceType":{"stringValue":"couple"},"sourceId":{"stringValue":"__migration_rls_pair"},"sourceKey":{"stringValue":"couple/__migration_rls_pair"}}'),
 ('voiceCalls/__migration_rls_call/candidates/a','{"owner":{"stringValue":"__migration_rls_owner"}}')
) AS fixtures(p,f);
SET LOCAL ROLE neural_api;
SELECT set_config('neural.uid','__migration_rls_chat_only',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'couples/__migration_rls_pair%')<>0 THEN RAISE EXCEPTION 'chat_contact_leaked_couple'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'chats/__migration_rls_chat%')<>2 THEN RAISE EXCEPTION 'chat_member_cannot_read_chat'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path='chatMedia/__migration_rls_active/chunks/0')<>1 THEN RAISE EXCEPTION 'active_media_not_readable'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path='chatMedia/__migration_rls_expired/chunks/0')<>0 THEN RAISE EXCEPTION 'expired_media_readable'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'voiceCalls/__migration_rls_call%')<>0 THEN RAISE EXCEPTION 'call_leaked_to_contact'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'chatAccounts/__migration_rls_owner/%')<>0 THEN RAISE EXCEPTION 'address_book_leaked'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path='accountCodeAliases/__migration_rls_code')<>0 THEN RAISE EXCEPTION 'login_alias_leaked'; END IF;
END $$;
SELECT set_config('neural.uid','__migration_rls_partner',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'couples/__migration_rls_pair%')<>2 THEN RAISE EXCEPTION 'couple_member_access_failed'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'chats/__migration_rls_chat%')<>0 THEN RAISE EXCEPTION 'couple_membership_grants_private_chat'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'voiceCalls/__migration_rls_call%')<>2 THEN RAISE EXCEPTION 'call_participant_access_failed'; END IF;
END $$;
SELECT set_config('neural.uid','__migration_rls_owner',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE 'chatAccounts/__migration_rls_owner/%')<>1 THEN RAISE EXCEPTION 'own_address_book_missing'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path='accountCodeAliases/__migration_rls_code')<>1 THEN RAISE EXCEPTION 'own_alias_missing'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path='accountLoginCodes/__migration_rls_owner')<>1 THEN RAISE EXCEPTION 'own_login_code_missing'; END IF;
 IF (SELECT count(*) FROM neural.documents WHERE path='config/__migration_rls_private')<>0 THEN RAISE EXCEPTION 'private_config_public'; END IF;
 IF has_table_privilege(current_user,'neural.documents','INSERT') OR has_table_privilege(current_user,'neural.documents','UPDATE') OR has_table_privilege(current_user,'neural.documents','DELETE') THEN RAISE EXCEPTION 'public_api_has_write_privilege'; END IF;
END $$;
SELECT set_config('neural.uid','',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM neural.documents WHERE path LIKE '%__migration_rls_%')<>0 THEN RAISE EXCEPTION 'anonymous_private_data_access'; END IF;
END $$;
SET LOCAL ROLE neural_sync;
INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document)
 VALUES('config/__migration_rls_sync','config','config','__migration_rls_sync',
 '{"fields":{"value":{"integerValue":"1"}},"updateTime":"2026-01-01T00:00:00Z"}')
 ON CONFLICT(path) DO UPDATE SET document=EXCLUDED.document,revision=DEFAULT,changed_at=now();
INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document)
 VALUES('config/__migration_rls_sync','config','config','__migration_rls_sync',
 '{"fields":{"value":{"integerValue":"2"}},"updateTime":"2026-01-02T00:00:00Z"}')
 ON CONFLICT(path) DO UPDATE SET document=EXCLUDED.document,revision=DEFAULT,changed_at=now()
 WHERE (EXCLUDED.document->>'updateTime')::timestamptz>(neural.documents.document->>'updateTime')::timestamptz;
DO $$ BEGIN
 IF (SELECT document #>> '{fields,value,integerValue}' FROM neural.documents WHERE path='config/__migration_rls_sync')<>'2' THEN RAISE EXCEPTION 'mirror_upsert_failed'; END IF;
END $$;
DELETE FROM neural.documents WHERE path='config/__migration_rls_sync';
ROLLBACK;
SELECT 'rls_checks_passed';
