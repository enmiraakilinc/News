import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const migration = async name =>
  readFile(new URL(`../sql/${name}`, import.meta.url), 'utf8');

test('later SQL policies preserve chat typing reads and owner-only writes', async()=>{
 const mediaExpiry=await migration('006_media_expiry.sql');
 const presence=await migration('007_presence.sql');
 assert.match(mediaExpiry,/n=4 AND parts\[3\] IN \('messages','typing'\)/);
 assert.match(presence,/n=4 AND parts\[3\] IN \('messages','typing'\)/);
 assert.match(presence,/a\[3\]='typing' THEN RETURN a\[4\]=uid AND neural\.member/);
});
