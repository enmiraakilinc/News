// Eski gizli kelimenin giriş kaydı silinmişse çifti hash ile bulur ve üyeliği geri açar.
import {getFirestore, FieldValue} from 'firebase-admin/firestore';
import {ApiError} from './access.mjs';

export async function restoreSecretLogin(pool, auth, hash) {
 if (!auth.uid) throw new ApiError(401, 'unauthenticated', 'Yeniden giriş yap.');
 if (!/^[a-f0-9]{64}$/.test(hash ?? '')) throw new ApiError(400, 'invalid-argument', 'Gizli kelimeyi gir.');
 const invitePath = 'invites/secret-' + hash;
 let coupleId = null;
 try {
  const invite = await getFirestore().doc(invitePath).get();
  if (invite.exists) coupleId = invite.data()?.coupleId ?? null;
  if (!coupleId) {
   const found = await getFirestore().collection('couples').where('secretCheck', '==', hash).limit(2).get();
   if (found.size === 1) coupleId = found.docs[0].id;
  }
 } catch {}
 if (!coupleId) {
  const rows = await pool.query(
   "SELECT document_id FROM neural.documents WHERE collection_id='couples' AND document #>> '{fields,secretCheck,stringValue}'=$1 LIMIT 2",
   [hash],
  );
  if (rows.rows.length === 1) coupleId = rows.rows[0].document_id;
 }
 if (!coupleId) throw new ApiError(404, 'not-found', 'Bu gizli kelimeyle açık bir bağ bulunamadı.');
 try {
  await getFirestore().doc(invitePath).set({coupleId}, {merge: true});
  await getFirestore().doc('couples/' + coupleId).update({
   members: FieldValue.arrayUnion(auth.uid),
   joinProof: hash,
  });
 } catch {}
 const db = await pool.connect();
 try {
  await db.query('BEGIN');
  await db.query('SET LOCAL ROLE neural_writer');
  const couplePath = 'couples/' + coupleId;
  const current = await db.query('SELECT document FROM neural.documents WHERE path=$1', [couplePath]);
  if (current.rows[0]) {
   const document = current.rows[0].document;
   const values = document.fields?.members?.arrayValue?.values ?? [];
   if (!values.some((item) => item.stringValue === auth.uid)) values.push({stringValue: auth.uid});
   document.fields = document.fields ?? {};
   document.fields.members = {arrayValue: {values}};
   document.fields.joinProof = {stringValue: hash};
   await db.query('UPDATE neural.documents SET document=$2::jsonb, changed_at=now() WHERE path=$1', [couplePath, JSON.stringify(document)]);
  }
  await db.query(
   `INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document)
    VALUES($1,'invites','invites',$2,$3::jsonb)
    ON CONFLICT (path) DO UPDATE SET document=EXCLUDED.document, changed_at=now()`,
   [invitePath, 'secret-' + hash, JSON.stringify({fields: {coupleId: {stringValue: coupleId}}})],
  );
  await db.query('COMMIT');
 } catch {
  await db.query('ROLLBACK');
 } finally {
  db.release();
 }
 return {ok: true};
}
