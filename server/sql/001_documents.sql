CREATE SCHEMA IF NOT EXISTS neural;
CREATE TABLE IF NOT EXISTS neural.documents (
 path text PRIMARY KEY CHECK (path <> '' AND path !~ '(^/|/$|//)'),
 parent_path text NOT NULL,
 collection_id text NOT NULL,
 document_id text NOT NULL,
 document jsonb NOT NULL CHECK (jsonb_typeof(document) = 'object'),
 revision bigint GENERATED ALWAYS AS IDENTITY,
 changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS documents_parent_id ON neural.documents(parent_path, document_id);
CREATE INDEX IF NOT EXISTS documents_collection_id ON neural.documents(collection_id);
CREATE INDEX IF NOT EXISTS documents_changed ON neural.documents(changed_at);
CREATE TABLE IF NOT EXISTS neural.migration_runs (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 read_time timestamptz NOT NULL,
 document_count bigint NOT NULL,
 canonical_sha256 text NOT NULL,
 imported_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE neural.documents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON SCHEMA neural FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA neural FROM PUBLIC;
