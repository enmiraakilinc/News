-- Gizli kelimeyle katılım: uygulama katmanı kanıtı doğruladığında eski satır RLS'e takılmaz.
DO $$
DECLARE def text;
BEGIN
 def:=pg_get_functiondef('neural.write_scope(text,jsonb,text)'::regprocedure);
 IF position('neural.join_path' in def)=0 THEN
  def:=replace(def,'IF n=2 THEN RETURN neural.member(''couples'',a[2],uid) OR',
   'IF n=2 THEN RETURN neural.member(''couples'',a[2],uid) OR current_setting(''neural.join_path'',true)=p OR');
  EXECUTE def;
 END IF;
END $$;
