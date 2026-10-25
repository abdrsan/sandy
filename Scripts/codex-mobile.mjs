#!/usr/bin/env node
// An explicitly launched, managed Codex session. Never attaches to Desktop or
// changes its approval policy. Uses the installed CLI's own authentication.
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { promises as fs } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { randomUUID, createHash } from 'node:crypto';
const prompt=process.argv.slice(2).join(' ');
if(!prompt) { process.stderr.write('Usage: node Scripts/codex-mobile.mjs "task"\n');process.exit(64); }
const root=process.env.SANDY_MOBILE_DIR ?? path.join(homedir(),'Library/Application Support/Sandy/Mobile');
const child=spawn(process.env.SANDY_CODEX_EXECUTABLE ?? 'codex',['app-server','--listen','stdio://'],{stdio:['pipe','pipe','inherit'],shell:false});
const pending=new Map();let n=100;let thread;let finished=false;const cancellations=new Map();
const send=x=>child.stdin.write(JSON.stringify(x)+'\n');
const request=(method,params)=>new Promise((resolve,reject)=>{const id=++n;const timeout=setTimeout(()=>{pending.delete(id);reject(Error('Codex RPC timeout'));},30000);pending.set(id,{resolve:x=>{clearTimeout(timeout);resolve(x)},reject:x=>{clearTimeout(timeout);reject(x)}});send({id,method,params})});
async function mobileDecision(params,method,signal) {
  const stamp=Number(await fs.readFile(path.join(root,'enabled'),'utf8'));if(Math.abs(Date.now()/1000-stamp)>8) return 'decline';
  const context=JSON.stringify({method,...params});if(Buffer.byteLength(context)>24000) return 'decline';
  const id=randomUUID(),digest=createHash('sha256').update(context).digest('hex');
  const approval={id,source:'codex',session:params.threadId,tool:method.includes('fileChange')?'File change':'Command',context,digest,challenge:randomUUID()+randomUUID(),expiresAt:Date.now()+90000};
  const folder=path.join(root,'requests'),file=path.join(folder,id+'.json'),response=path.join(folder,id+'.response');
  await fs.mkdir(folder,{recursive:true,mode:0o700});await fs.writeFile(file,JSON.stringify(approval),{mode:0o600,flag:'wx'});
  try {
    while(Date.now()<approval.expiresAt && !signal.aborted) {
      try {const decision=JSON.parse(await fs.readFile(response,'utf8'));if(decision.id===id&&decision.digest===digest&&['allow','deny'].includes(decision.action)) return decision.action==='allow'?'accept':'decline';} catch {}
      const heartbeat=Number(await fs.readFile(path.join(root,'enabled'),'utf8'));if(Math.abs(Date.now()/1000-heartbeat)>8) return 'decline';
      await new Promise(resolve=>setTimeout(resolve,200));
    }
    return 'decline';
  } finally {await fs.rm(file,{force:true});await fs.rm(response,{force:true});}
}
async function handle(message) {
  if(message.id!=null && pending.has(message.id) && !message.method) {
    const p=pending.get(message.id);pending.delete(message.id);message.error?p.reject(Error('Codex request rejected')):p.resolve(message.result);return;
  }
  if(message.id!=null && message.method) {
    if(['item/commandExecution/requestApproval','item/fileChange/requestApproval'].includes(message.method)) {
      const control=new AbortController();cancellations.set(String(message.id),control);
      const decision=await mobileDecision(message.params,message.method,control.signal).catch(()=>'decline');
      if(!control.signal.aborted) send({id:message.id,result:{decision}});
      cancellations.delete(String(message.id));
    } else if(message.method==='item/permissions/requestApproval') send({id:message.id,result:{permissions:{},scope:'turn'}});
    else send({id:message.id,error:{code:-32601,message:'Unsupported interactive request; use the standard Codex client'}});
    return;
  }
  if(message.method==='serverRequest/resolved') cancellations.get(String(message.params?.requestId))?.abort();
  if(message.method==='item/agentMessage/delta') process.stdout.write(message.params?.delta ?? '');
  if(message.method==='turn/completed') {finished=true;for(const c of cancellations.values())c.abort();child.stdin.end();setTimeout(()=>child.kill(),1000).unref();}
}
createInterface({input:child.stdout,maxLineLength:1<<20}).on('line',line=>{if(line.length>1<<20) {child.kill();return;}try{void handle(JSON.parse(line)).catch(()=>child.kill());}catch{child.kill();}});
child.on('error',()=>{process.stderr.write('Could not start Codex. Set SANDY_CODEX_EXECUTABLE to the installed CLI.\n');process.exitCode=1});
child.on('exit',()=>{for(const c of cancellations.values())c.abort();if(!finished)process.exitCode=1;for(const p of pending.values())p.reject(Error('Codex exited'));});
for(const sig of ['SIGINT','SIGTERM'])process.on(sig,()=>{for(const c of cancellations.values())c.abort();child.kill(sig);});
try {
 await request('initialize',{clientInfo:{name:'sandy_mobile',title:'Sandy mobile approvals',version:'0.1.0'}});send({method:'initialized',params:{}});
 const result=await request('thread/start',{cwd:process.cwd(),approvalPolicy:'unlessTrusted',sandbox:'workspaceWrite'});thread=result.thread.id;
 await request('turn/start',{threadId:thread,input:[{type:'text',text:prompt}]});
} catch { process.stderr.write('Codex integration failed; no pending action was approved.\n');child.kill();process.exitCode=1; }
