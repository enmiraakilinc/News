export async function streamReleaseAsset(env,fetcher,asset,version) {
  let stage='asset-api';
  const fail=code=>Response.json({message:'Güncelleme indirilemiyor. Daha sonra yeniden dene.',code},{status:503,headers:{'Cache-Control':'no-store'}});
  try {
    const repo=env.GITHUB_RELEASE_REPO;
    if(!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo??'')||!/^\d+$/.test(asset??'')||!/^\d+\.\d+\.\d+$/.test(version??''))return fail('invalid-release');
    const headers={Authorization:`Bearer ${env.GITHUB_RELEASE_TOKEN.trim()}`,Accept:'application/octet-stream','User-Agent':'private-app-updater','X-GitHub-Api-Version':'2022-11-28'};
    const repositoryId=env.GITHUB_RELEASE_REPOSITORY_ID;
    if(repositoryId!==undefined&&!/^\d{1,20}$/.test(repositoryId))return fail('invalid-repository');
    // A repository rename returns a 301 to its numeric API URL. Starting with
    // that stable URL avoids forwarding credentials through arbitrary redirects.
    const root=repositoryId?`https://api.github.com/repositories/${repositoryId}`:`https://api.github.com/repos/${repo}`;
    let apk=await fetcher(`${root}/releases/assets/${asset}`,{headers,redirect:'manual'});
    if(apk.status===302){
      stage='asset-redirect';
      const location=new URL(apk.headers.get('Location'));
      if(location.protocol!=='https:'||!['release-assets.githubusercontent.com','objects.githubusercontent.com'].includes(location.hostname))return fail('untrusted-redirect');
      stage='asset-fetch';
      apk=await fetcher(location.toString(),{redirect:'manual'});
    }
    if(!apk.ok)return fail(`upstream-${apk.status}`);
    const output=new Headers({'Content-Type':'application/vnd.android.package-archive','Cache-Control':'private, no-store','Content-Disposition':`attachment; filename="update-${version}.apk"`,'X-Content-Type-Options':'nosniff'});
    const length=apk.headers.get('Content-Length');if(length)output.set('Content-Length',length);
    stage='asset-stream';return new Response(apk.body,{status:200,headers:output});
  }catch{return fail(stage);}
}
