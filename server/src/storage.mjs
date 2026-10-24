import {statfs} from 'node:fs/promises';

let cached, validUntil = 0;
export async function storageStatus(pool) {
  if (cached && Date.now() < validUntil) return cached;
  const [disk, result] = await Promise.all([
    statfs('/'),
    pool.query("SELECT pg_database_size(current_database())::text AS bytes"),
  ]);
  const limitBytes = disk.blocks * disk.bsize;
  const freeBytes = disk.bavail * disk.bsize;
  const bytes = limitBytes - freeBytes;
  const checkedAt = new Date().toISOString();
  cached = {provider:'oracle',bytes,limitBytes,freeBytes,
    databaseBytes:Number(result.rows[0].bytes),checkedAt,observedAt:checkedAt,
    warning:bytes >= limitBytes * 0.8,stale:false};
  validUntil = Date.now() + 60000;
  return cached;
}
