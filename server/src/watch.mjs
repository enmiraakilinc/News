// Saat uygulamasının haber, sohbet ve mesaj uçlarıdır.
import {readFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
import {ApiError} from './access.mjs';
import {encodeFields} from './firestore_codec.mjs';

const news = JSON.parse(readFileSync(new URL('./watch_news.json', import.meta.url), 'utf8'))
  .sort((a, b) => b.publishedAt.localeCompare(a.publishedAt))
  .slice(0, 10);

const textOf = (fields, key) => fields?.[key]?.stringValue ?? '';
const membersOf = doc => (doc?.fields?.members?.arrayValue?.values ?? [])
  .map(item => item.stringValue).filter(Boolean);

function titleOf(doc, uid) {
  const title = textOf(doc.fields, 'title');
  if (title) return title;
  const names = doc.fields?.names?.mapValue?.fields ?? {};
  const other = Object.entries(names).filter(([id]) => id !== uid).map(([, value]) => value.stringValue).filter(Boolean);
  return other[0] || 'Sohbet';
}

export function watchNews() {
  return {items: news};
}

async function uidForToken(pool, token) {
  if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(token)) {
    throw new ApiError(401, 'unauthenticated', 'Saat jetonu geçersiz.');
  }
  await pool.query(`CREATE TABLE IF NOT EXISTS neural.watch_tokens (
    token text PRIMARY KEY,
    uid text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
  )`);
  const saved = await pool.query('SELECT uid FROM neural.watch_tokens WHERE token=$1', [token]);
  if (saved.rows[0]?.uid) return saved.rows[0].uid;
  if (process.env.WATCH_TOKEN && token === process.env.WATCH_TOKEN && process.env.WATCH_UID) {
    return process.env.WATCH_UID;
  }
  throw new ApiError(401, 'unauthenticated', 'Saat jetonu tanınmadı.');
}

export async function watchChats(pool, token) {
  const uid = await uidForToken(pool, token);
  const chats = await pool.query(
    `SELECT document_id, document FROM neural.documents
     WHERE collection_id='chats' AND parent_path='chats'
       AND document #> '{fields,members,arrayValue,values}' @> $1::jsonb
     ORDER BY document #>> '{fields,updatedAt,timestampValue}' DESC NULLS LAST
     LIMIT 20`,
    [JSON.stringify([{stringValue: uid}])],
  );
  const items = [];
  for (const row of chats.rows) {
    const doc = row.document;
    const messages = await pool.query(
      `SELECT document_id, document FROM neural.documents
       WHERE parent_path=$1
       ORDER BY document #>> '{fields,sentAt,timestampValue}' DESC NULLS LAST
       LIMIT 15`,
      [`chats/${row.document_id}/messages`],
    );
    items.push({
      id: row.document_id,
      title: titleOf(doc, uid),
      messages: messages.rows.reverse().map(message => ({
        id: message.document_id,
        text: textOf(message.document.fields, 'text').slice(0, 500),
        sender: textOf(message.document.fields, 'sender'),
        sentAt: message.document.fields?.sentAt?.timestampValue ?? null,
        fromMe: textOf(message.document.fields, 'sender') === uid,
      })),
    });
  }
  return {uid, chats: items};
}

export async function watchSend(pool, body) {
  const uid = await uidForToken(pool, body?.token);
  const chatId = body?.chatId;
  const text = typeof body?.text === 'string' ? body.text.trim() : '';
  if (typeof chatId !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(chatId)) {
    throw new ApiError(400, 'invalid-argument', 'Sohbet bulunamadı.');
  }
  if (!text || text.length > 500) throw new ApiError(400, 'invalid-argument', 'Mesaj 1–500 karakter olmalı.');
  const chat = await pool.query(
    `SELECT document FROM neural.documents WHERE path=$1`,
    [`chats/${chatId}`],
  );
  const members = membersOf(chat.rows[0]?.document);
  if (!members.includes(uid)) throw new ApiError(403, 'permission-denied', 'Bu sohbete yazma iznin yok.');
  const messageId = randomBytes(16).toString('hex');
  const path = `chats/${chatId}/messages/${messageId}`;
  const now = new Date();
  const stamp = now.toISOString();
  const document = {
    name: `projects/${process.env.FIREBASE_PROJECT_ID}/databases/(default)/documents/${path}`,
    fields: encodeFields({
      sender: uid,
      text,
      sentAt: now,
      openAt: now,
      readBy: [uid],
      replyTo: null,
      scheduled: false,
    }),
    createTime: stamp,
    updateTime: stamp,
  };
  await pool.query(
    `INSERT INTO neural.documents(path,parent_path,collection_id,document_id,document,origin)
     VALUES($1,$2,'messages',$3,$4::jsonb,'postgres')`,
    [path, `chats/${chatId}/messages`, messageId, JSON.stringify(document)],
  );
  await pool.query(
    `UPDATE neural.documents
     SET document=jsonb_set(document, '{fields,updatedAt}', $2::jsonb, true), changed_at=now()
     WHERE path=$1`,
    [`chats/${chatId}`, JSON.stringify({timestampValue: stamp})],
  );
  return {ok: true, messageId, path, uid};
}
