// Kayıtları ve sürüm listesini sunucudan çekip düğmeleri bağlar.
async function loadReleases() {
  const body = document.querySelector('#releases');
  body.replaceChildren();
  const response = await fetch('/admin/api/releases');
  const data = await response.json();
  const active = (data.releases || []).find((row) => row.name === data.active);
  for (const row of data.releases || []) {
    const tr = document.createElement('tr');
    const name = document.createElement('td');
    name.textContent = row.name;
    const code = document.createElement('td');
    code.textContent = String(row.code);
    const sha = document.createElement('td');
    sha.className = 'sha';
    sha.textContent = row.sha256;
    const linkCell = document.createElement('td');
    const link = document.createElement('a');
    link.href = '/updates/apk?version=' + encodeURIComponent(row.name);
    link.textContent = 'İndir';
    linkCell.append(link);
    const action = document.createElement('td');
    if (row.name === data.active) action.textContent = data.rollback ? 'Geri alınan sürüm' : 'Aktif';
    else if (!active || row.code < active.code) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = 'Önceki Sürüme Geri Dön';
      button.addEventListener('click', async () => {
        const result = await fetch('/admin/api/rollback', {
          method: 'POST',
          headers: {'content-type': 'application/json'},
          body: JSON.stringify({name: row.name}),
        });
        if (result.ok) loadReleases();
      });
      action.append(button);
    }
    tr.append(name, code, sha, linkCell, action);
    body.append(tr);
  }
}
async function loadLogs() {
  const body = document.querySelector('#rows');
  const empty = document.querySelector('#empty');
  body.replaceChildren();
  const response = await fetch('/admin/api/logs');
  const data = await response.json();
  const rows = data.rows || [];
  empty.style.display = rows.length ? 'none' : 'block';
  for (const row of rows) {
    const tr = document.createElement('tr');
    for (const value of [row.requested_at, row.email, row.status, row.detail]) {
      const td = document.createElement('td');
      td.textContent = value || '';
      tr.append(td);
    }
    body.append(tr);
  }
}
document.querySelector('#refresh').addEventListener('click', () => { loadReleases(); loadLogs(); });
loadReleases();
loadLogs();
