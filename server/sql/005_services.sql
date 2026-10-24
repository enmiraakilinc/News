-- Privileged service reads cannot be used by phone queries.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='neural_service') THEN
  CREATE ROLE neural_service NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
 END IF;
END $$;
GRANT neural_service TO neural_api;
GRANT USAGE ON SCHEMA neural TO neural_service;
GRANT SELECT ON neural.documents,neural.settings TO neural_service;
DROP POLICY IF EXISTS service_reads ON neural.documents;
CREATE POLICY service_reads ON neural.documents FOR SELECT TO neural_service
 USING((collection_id IN ('accountCodeAliases','updateAccess','config','voiceCalls','chats','couples') AND parent_path=collection_id)
  OR (path ~ '^chatAccounts/[^/]+/(callDevices|wakeDevices|wakePermissions)/[^/]+$'));
CREATE TABLE IF NOT EXISTS neural.service_limits(
 key text PRIMARY KEY,started_at timestamptz NOT NULL DEFAULT now(),attempts integer NOT NULL
);
CREATE TABLE IF NOT EXISTS neural.wake_jobs(
 key text PRIMARY KEY,payload jsonb NOT NULL,fire_at timestamptz NOT NULL,
 retry_at timestamptz NOT NULL DEFAULT now(),attempts integer NOT NULL DEFAULT 0,
 lease_until timestamptz
);
REVOKE ALL ON neural.service_limits,neural.wake_jobs FROM PUBLIC;
GRANT SELECT,INSERT,UPDATE,DELETE ON neural.service_limits,neural.wake_jobs TO neural_service;
