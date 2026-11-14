-- Kullanıcı adı ve e-posta, mevcut kimliğe bağlanır. Eski kodlar durur.
DO $$
DECLARE def text; expr text;
BEGIN
 def:=pg_get_functiondef('neural.write_scope(text,jsonb,text)'::regprocedure);
 IF position('accountUsernames' in def)=0 THEN
  def:=replace(def,
   'IF a[1]=''accountCodeAliases'' AND n=2 THEN RETURN d #>> ''{fields,owner,stringValue}''=uid; END IF;',
   'IF a[1]=''accountCodeAliases'' AND n=2 THEN RETURN d #>> ''{fields,owner,stringValue}''=uid; END IF;
 IF a[1] IN (''accountUsernames'',''accountEmailAliases'') AND n=2 THEN RETURN d #>> ''{fields,owner,stringValue}''=uid; END IF;
 IF a[1] IN (''accountLoginNames'',''accountLoginEmails'') AND n=2 THEN RETURN a[2]=uid; END IF;');
  EXECUTE def;
 END IF;
 def:=pg_get_functiondef('neural.can_read(text,jsonb,text)'::regprocedure);
 IF position('accountUsernames' in def)=0 THEN
  def:=replace(def,
   'IF n=2 AND parts[1]=''accountCodeAliases'' THEN RETURN d #>> ''{fields,owner,stringValue}''=uid; END IF;',
   'IF n=2 AND parts[1] IN (''accountCodeAliases'',''accountUsernames'',''accountEmailAliases'') THEN RETURN d #>> ''{fields,owner,stringValue}''=uid; END IF;
 IF n=2 AND parts[1] IN (''accountLoginNames'',''accountLoginEmails'') THEN RETURN parts[2]=uid; END IF;');
  EXECUTE def;
 END IF;
 SELECT qual INTO expr FROM pg_policies
  WHERE schemaname='neural' AND tablename='documents' AND policyname='service_reads';
 IF expr IS NOT NULL AND position('accountUsernames' in expr)=0 THEN
  EXECUTE 'DROP POLICY service_reads ON neural.documents';
  EXECUTE 'CREATE POLICY service_reads ON neural.documents FOR SELECT TO neural_service USING ('
   || replace(expr, '''accountCodeAliases''', '''accountCodeAliases'',''accountUsernames'',''accountEmailAliases''')
   || ')';
 END IF;
END $$;
