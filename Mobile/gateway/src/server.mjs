import http from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
const hash = x => createHash('sha256').update(x).digest();
const validID = x => typeof x === 'string' && /^[a-zA-Z0-9_-]{22,64}$/.test(x);
const validHash = x => typeof x === 'string' && /^[0-9a-f]{64}$/.test(x);
export class Relay {
  constructor({ adminToken, clock = Date.now, push = async () => {}, changed = () => {}, providers = {} }) {
    if (typeof adminToken !== 'string' || adminToken.length < 43) throw Error('A 256-bit admin token is required');
    this.providers=providers; this.changed=changed; this.admin = hash(adminToken); this.clock = clock; this.push = push; this.rooms = new Map(); this.limits = new Map();
  }
  equal(a, b) { return a.length === b.length && timingSafeEqual(a, b); }
  limited(key, max) {
    const now = this.clock();
    if (this.limits.size > 10000) this.limits = new Map([...this.limits].filter(([,v]) => v.until > now));
    const bucket = this.limits.get(key) ?? { n: 0, until: now + 60000 };
    if (bucket.until <= now) { bucket.n = 0; bucket.until = now + 60000; }
    bucket.n++; this.limits.set(key, bucket); return bucket.n > max;
  }
  async body(req) {
    let size = 0; const parts = [];
    for await (const chunk of req) {
      size += chunk.length; if (size > 70000) throw Object.assign(Error(), { status: 413 }); parts.push(chunk);
    }
    try { return JSON.parse(Buffer.concat(parts).toString('utf8')); } catch { throw Object.assign(Error(), { status: 400 }); }
  }
  async handle(req, res) {
    const respond = (status, value = {}) => {
      res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store',
        'x-content-type-options': 'nosniff', 'strict-transport-security': 'max-age=31536000' });
      res.end(JSON.stringify(value));
    };
    try {
      if (req.headers.origin) return respond(403); // Native clients only. No browser CORS surface.
      const ip = req.socket.remoteAddress ?? '';
      if (this.limited('ip:' + ip, 600)) return respond(429);
      const url = new URL(req.url, 'http://relay.invalid');
      if (url.pathname === '/health' && req.method === 'GET') return respond(200, { service: 'sandy-relay', version: 1 });
      const token = req.headers.authorization?.replace(/^Bearer /, '') ?? '';
      if (req.method === 'POST' && url.pathname === '/v1/rooms') {
        if (!this.equal(hash(token), this.admin)) return respond(401);
        const b = await this.body(req);
        if (!validID(b.room) || !validHash(b.macHash) || !validHash(b.phoneHash) || b.macHash === b.phoneHash) return respond(400);
        const old = this.rooms.get(b.room);
        if (old && (old.macHash !== b.macHash || old.phoneHash !== b.phoneHash)) return respond(409);
        if (!old && this.rooms.size >= 100) return respond(429);
        if (!old) this.rooms.set(b.room, { ...b, queues: { mac: [], phone: [] }, seq: 0, push: null, livePush: null, expires: this.clock()+7*86400000 });
        this.changed(); return respond(200);
      }
      const match = /^\/v1\/rooms\/([A-Za-z0-9_-]{22,64})(?:\/(messages|push))?$/.exec(url.pathname);
      if (!match) return respond(404);
      const room = this.rooms.get(match[1]); const role = req.headers['x-sandy-role'];
      if (!room || room.expires < this.clock()) { this.rooms.delete(match[1]); return respond(401); }
      if (!['mac','phone'].includes(role) || !this.equal(hash(token), Buffer.from(room[role+'Hash'], 'hex'))) return respond(401);
      if (this.limited(match[1]+role, 240)) return respond(429);
      if(room.expires < this.clock()+6*86400000) { room.expires=this.clock()+7*86400000; this.changed(); }
      if (!match[2] && req.method === 'DELETE' && role === 'mac') { this.rooms.delete(match[1]); this.changed(); return respond(200); }
      if (match[2] === 'push' && req.method === 'POST' && role === 'phone') {
        const b = await this.body(req);
        if (!['apns','apns-live','fcm'].includes(b.platform) || typeof b.token !== 'string' || b.token.length > 4096 ||
            !/^[A-Za-z0-9:_-]{32,4096}$/.test(b.token)) return respond(400);
        if(b.platform==='apns-live') room.livePush={platform:b.platform,token:b.token}; else room.push={platform:b.platform,token:b.token}; this.changed(); return respond(200,{configured:this.providers[b.platform]===true});
      }
      if (match[2] !== 'messages') return respond(404);
      if (req.method === 'GET') {
        const after = Number(url.searchParams.get('after') ?? 0);
        if (!Number.isSafeInteger(after) || after < 0) return respond(400);
        room.queues[role] = room.queues[role].filter(x => x.expires > this.clock());
        return respond(200, { cursor: room.seq, messages: room.queues[role].filter(x => x.seq > after).map(x => x.envelope) });
      }
      if (req.method !== 'POST') return respond(405);
      const b = await this.body(req); const e = b.envelope;
      if (!e || e.version !== 1 || e.room !== match[1] || typeof e.id !== 'string' || !/^[0-9a-f-]{36}$/.test(e.id) ||
          !Number.isSafeInteger(e.sentAt) || Math.abs(this.clock()-e.sentAt)>120000 ||
          !['senderKey','encapsulatedKey','ciphertext'].every(k => typeof e[k] === 'string' && /^[A-Za-z0-9+/]+=*$/.test(e[k])) ||
          e.senderKey.length !== 88 || e.encapsulatedKey.length !== 88 || e.ciphertext.length > 65536) return respond(400);
      if(b.live && (!Number.isInteger(b.live.working) || !Number.isInteger(b.live.waiting) ||
          b.live.working<0 || b.live.working>2000 || b.live.waiting<0 || b.live.waiting>32)) return respond(400);
      const destination = role === 'mac' ? 'phone' : 'mac';
      const queue = room.queues[destination].filter(x => x.expires > this.clock());
      if (queue.some(x => x.envelope.id === e.id)) return respond(200); // Retry is idempotent.
      if (queue.length >= 32) queue.shift();
      queue.push({ seq: ++room.seq, envelope: e, expires: this.clock()+120000 }); room.queues[destination] = queue;
      respond(200);
      if(role==='mac' && b.live && room.livePush && !this.limited('live:'+match[1], b.notify ? 15 : 4)) {
        this.push({...room.livePush, state:{working:b.live.working, waiting:b.live.waiting}}).catch(()=>{});
      }
      if (role === 'mac' && b.notify === true && room.push && !this.limited('push:'+match[1], 15)) {
        // Never forward ciphertext, commands, names, paths or IDs in visible push text.
        this.push(room.push).catch(() => {});
      }
    } catch (e) { if (!res.headersSent) respond(e.status ?? 500); }
  }
}
export function server(relay) {
  const s = http.createServer((req, res) => void relay.handle(req, res));
  s.requestTimeout = 15000; s.headersTimeout = 10000; s.maxHeadersCount = 30; s.maxConnections = 256;
  return s;
}
