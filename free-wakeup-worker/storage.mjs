export const freeStorageBytes = 1024 ** 3;
export async function checkStorage(env, {fetch: fetcher = fetch, token} = {}) {
  const now = new Date();
  const params = new URLSearchParams({filter: 'metric.type="firestore.googleapis.com/storage/data_and_index_storage_bytes"',
    'interval.startTime': new Date(now.getTime() - 24*60*60*1000).toISOString(), 'interval.endTime': now.toISOString(), pageSize: '1'});
  const response = await fetcher(`https://monitoring.googleapis.com/v3/projects/${env.FIREBASE_PROJECT_ID}/timeSeries?${params}`,
    {headers: {Authorization: `Bearer ${await token()}`}});
  if (!response.ok) throw Error('storage-metric-unavailable');
  const series = (await response.json()).timeSeries ?? [];
  const point = series.find(item => (item.resource?.labels?.database_id ?? '(default)') === '(default)')?.points?.[0];
  const bytes = Number(point?.value?.int64Value);
  if (!Number.isSafeInteger(bytes) || bytes < 0 || !point?.interval?.endTime) throw Error('storage-metric-missing');
  const report = {bytes, limitBytes: freeStorageBytes, percent: Math.round(bytes/freeStorageBytes*10000)/100,
    checkedAt: now.toISOString(), observedAt: point.interval.endTime, warning: bytes >= freeStorageBytes*0.8};
  const object = env.WAKE_RATE.get(env.WAKE_RATE.idFromName('storage-reports'));
  const saved = await object.fetch(new Request('https://internal/storage', {method: 'PUT', body: JSON.stringify(report)}));
  if (!saved.ok) throw Error('storage-report-save-failed');
  return report;
}

export async function storageStatus(request, env, deps) {
  const auth = request.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ') || auth.length > 10000) return Response.json({message: 'Yeniden giriş yapmalısın.'}, {status:401});
  try {
    const login = await deps.fetch(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`,
      {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({idToken:auth.slice(7)})});
    if (!login.ok || !(await login.json()).users?.[0]?.localId) return Response.json({message:'Yeniden giriş yapmalısın.'},{status:401});
    const object = env.WAKE_RATE.get(env.WAKE_RATE.idFromName('storage-reports'));
    const claim = await object.fetch(new Request('https://internal/storage/reserve', {method:'POST'}));
    if (claim.ok) {
      try { await checkStorage(env, deps); } catch (_) {
        // Preserve the last sample and retry after ten minutes, not a full day.
        await object.fetch(new Request('https://internal/storage/failure',{method:'POST'}));
      }
    }
    const result = await object.fetch(new Request('https://internal/storage'));
    if (!result.ok) return Response.json({message:'Depolama ölçümü henüz alınamadı.'},{status:503});
    const report = await result.json();
    return Response.json({...report, stale:Date.now()-Date.parse(report.checkedAt) > 36*60*60*1000});
  } catch (_) { return Response.json({message:'Depolama durumu şu anda okunamadı.'},{status:503}); }
}
