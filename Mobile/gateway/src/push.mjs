import { readFile } from 'node:fs/promises';
import { createPrivateKey, sign } from 'node:crypto';
import http2 from 'node:http2';
const b64 = x => Buffer.from(typeof x === 'string' ? x : JSON.stringify(x)).toString('base64url');
function jwt(claims, header, key, algorithm) {
  const input = b64(header)+'.'+b64(claims);
  const signature = sign(algorithm, Buffer.from(input), algorithm === 'sha256' ? { key: createPrivateKey(key), dsaEncoding: 'ieee-p1363' } : key);
  return input+'.'+signature.toString('base64url');
}
export function pushSender(env) {
  let googleToken; let googleUntil = 0;
  return async ({platform, token, state}) => {
    if (platform === 'apns' || platform === 'apns-live') {
      if (!env.APNS_KEY_FILE || !env.APNS_TOPIC || !env.APNS_TEAM_ID || !env.APNS_KEY_ID) return;
      const now = Math.floor(Date.now()/1000);
      const auth = jwt({iss:env.APNS_TEAM_ID, iat:now}, {alg:'ES256',kid:env.APNS_KEY_ID}, await readFile(env.APNS_KEY_FILE,'utf8'), 'sha256');
      const host = env.APNS_SANDBOX === '1' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
      const session = http2.connect(host);
      await new Promise((resolve,reject) => {
        const timeout = setTimeout(()=>{session.destroy();reject(Error('timeout'));},10000);
        session.once('error',reject);
        const request = session.request({':method':'POST',':path':'/3/device/'+token,authorization:'bearer '+auth,
          'apns-topic':env.APNS_TOPIC+(platform==='apns-live'?'.push-type.liveactivity':''),'apns-push-type':platform==='apns-live'?'liveactivity':'alert','apns-priority':platform==='apns-live'?'5':'10','apns-expiration':String(now+120)});
        request.on('response',()=>{}); request.on('data',()=>{});
        request.once('error',reject); request.once('end',()=>{ clearTimeout(timeout);session.close();resolve(); });
        request.end(JSON.stringify(platform==='apns-live' ? {aps:{timestamp:now,event:'update','stale-date':now+60,'content-state':{working:state.working,waiting:state.waiting,status:state.waiting>0?'Needs your approval':'Agents working'}}} : {aps:{alert:{title:'Sandy',body:'An agent has an update. Open Sandy to review.'},sound:'default'}}));
      }).finally(()=>session.destroy());
    } else {
      if (!env.FCM_KEY_FILE) return;
      const key = JSON.parse(await readFile(env.FCM_KEY_FILE,'utf8'));
      if (!/^[a-z0-9-]+$/.test(key.project_id)) throw Error('Invalid Firebase project');
      if (!googleToken || googleUntil < Date.now()) {
        const now = Math.floor(Date.now()/1000);
        const assertion = jwt({iss:key.client_email, scope:'https://www.googleapis.com/auth/firebase.messaging',
          aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600},{alg:'RS256',typ:'JWT'},key.private_key,'RSA-SHA256');
        const response = await fetch('https://oauth2.googleapis.com/token',{method:'POST',signal:AbortSignal.timeout(10000),
          headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});
        if (!response.ok) throw Error('FCM auth failed');
        const result = await response.json(); googleToken = result.access_token; googleUntil=Date.now()+3000000;
      }
      await fetch('https://fcm.googleapis.com/v1/projects/'+key.project_id+'/messages:send',{method:'POST',signal:AbortSignal.timeout(10000),
        headers:{authorization:'Bearer '+googleToken,'content-type':'application/json'},
        body:JSON.stringify({message:{token,notification:{title:'Sandy',body:'An agent has an update. Open Sandy to review.'},android:{priority:'high',ttl:'120s'}}})});
    }
  };
}
