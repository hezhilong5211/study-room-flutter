"""Study room service. Python 3.10+, SQLite, no third-party runtime dependencies."""
import argparse
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).parent
# Keep None as “not a member” for existing clients; null days grants lifetime membership.
PERMANENT_MEMBERSHIP_UNTIL = 253402300799

def uid(): return secrets.token_hex(12)
def now(): return int(time.time())
def digest(value): return hashlib.sha256(value.encode()).hexdigest()
def password(value, salt): return hashlib.scrypt(value.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()

class Problem(Exception):
    def __init__(self, message, status=400): self.message, self.status = message, status

def require(ok, message, status=400):
    if not ok: raise Problem(message, status)

def text(data, key, maximum=100):
    value = data.get(key)
    require(isinstance(value, str) and 0 < len(value.strip()) <= maximum, f'{key} 不能为空或过长')
    return value.strip()

def expiry(data, key='days'):
    days = data.get(key)
    require(days is None or type(days) is int and 1 <= days <= 3650, '有效天数须为 1–3650，留空表示永久')
    return None if days is None else now() + days * 86400

class Service:
    def __init__(self, path, admin_password=None, development=False):
        self.path, self.development = path, development
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS records(kind TEXT NOT NULL,id TEXT NOT NULL,data TEXT NOT NULL,PRIMARY KEY(kind,id));
        CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT NOT NULL,expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS credentials(login TEXT PRIMARY KEY,user_id TEXT UNIQUE NOT NULL,salt TEXT NOT NULL,hash TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY AUTOINCREMENT,at INTEGER,actor TEXT,action TEXT,target TEXT);
        ''')
        with self.db:
            if not self.all('resources'):
                for kind, entries in {'background':[('library','静谧图书馆'),('forest','林间晨光'),('night','城市夜读'),('sea','海边书桌')], 'music':[('rain','雨声'),('piano','轻钢琴'),('forest','森林白噪音'),('silent','静音')], 'frame':[('starlight','星光环绕'),('blossom','樱花信笺'),('laurel','桂冠荣耀')]}.items():
                    for id_, name in entries: self.save('resources', {'id':kind+'-'+id_, 'key':id_, 'kind':kind,'name':name,'enabled':True,'url':'','priceCents':600,'durationDays':7})
            existing_admin=self.db.execute('SELECT user_id FROM credentials WHERE login=?',('admin',)).fetchone()
            if admin_password and existing_admin:
                require(self.get('users',existing_admin[0])['role']=='admin','admin 账号冲突，无法初始化管理员')
            if admin_password and not existing_admin:
                require(len(admin_password)>=12, '管理员密码至少 12 位')
                u = self.new_user('管理员', False); u['role']='admin'; u['profileComplete']=True; self.save('users',u)
                self.credential('admin',admin_password,u['id'])
    def all(self, kind): return [json.loads(r[0]) for r in self.db.execute('SELECT data FROM records WHERE kind=?',(kind,))]
    def get(self, kind, id_):
        row=self.db.execute('SELECT data FROM records WHERE kind=? AND id=?',(kind,id_)).fetchone()
        require(row is not None, '记录不存在',404)
        return json.loads(row[0])
    def save(self, kind, data): self.db.execute('INSERT INTO records VALUES(?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data',(kind,data['id'],json.dumps(data,ensure_ascii=False)))
    def delete(self, kind, id_): self.db.execute('DELETE FROM records WHERE kind=? AND id=?',(kind,id_))
    def log(self, actor, action, target): self.db.execute('INSERT INTO audit(at,actor,action,target) VALUES(?,?,?,?)',(now(),actor,action,str(target)))
    def new_user(self, name, guest):
        u={'id':uid(),'name':name,'avatar':'学','isGuest':guest,'profileComplete':False,'memberUntil':None,'role':'user','disabled':False,'activeFrameId':None,'friendIds':[]}
        self.save('users',u); return u
    def credential(self, login, pwd, user):
        require(len(pwd)>=10 and len(pwd)<=256,'密码需 10–256 位')
        require(not self.db.execute('SELECT 1 FROM credentials WHERE login=?',(login,)).fetchone(),'账号已存在',409)
        salt=secrets.token_hex(16)
        self.db.execute('INSERT INTO credentials VALUES(?,?,?,?)',(login,user,salt,password(pwd,salt)))
    def session(self,user):
        token=secrets.token_urlsafe(32)
        self.db.execute('INSERT INTO sessions VALUES(?,?,?)',(digest(token),user,now()+7*86400)); return {'token':token}
    def actor(self,token):
        row=self.db.execute('SELECT user_id FROM sessions WHERE token=? AND expires>?',(digest(token),now())).fetchone()
        require(row,'请先登录',401); u=self.get('users',row[0]); require(not u['disabled'],'账号已停用',403); return u
    def auth(self, op, d, token):
        if op=='guest': return self.session(self.new_user('访客',True)['id'])
        if op=='register':
            login=text(d,'login',80).lower(); pwd=text(d,'password',256)
            require(login!='admin','此账号名保留给系统管理员')
            u=self.actor(token) if token else self.new_user(text(d,'name'),False)
            require(u['isGuest'] or not token,'已注册账号不能重复升级')
            self.credential(login,pwd,u['id']); u.update(isGuest=False,name=text(d,'name')); self.save('users',u)
            self.db.execute('DELETE FROM sessions WHERE user_id=?',(u['id'],)); return self.session(u['id'])
        if op=='login':
            row=self.db.execute('SELECT user_id,salt,hash FROM credentials WHERE login=?',(text(d,'login',80),)).fetchone()
            require(row and hmac.compare_digest(password(text(d,'password',256),row[1]),row[2]),'账号或密码错误',401)
            require(not self.get('users',row[0])['disabled'],'账号已停用',403); return self.session(row[0])
        if op=='logout': self.db.execute('DELETE FROM sessions WHERE token=?',(digest(token),)); return {}
        raise Problem('未知认证操作',404)
    def registered(self,u,complete=False):
        require(not u['isGuest'],'请先注册',403)
        if complete: require(u['profileComplete'],'请完善资料',403)
    def valid(self,obj): return not obj.get('revoked',False) and (obj.get('expiresAt') is None or obj['expiresAt']>now())
    def owns(self,user,badge):
        b=self.get('badges',badge)
        return self.valid(b) and any(x['userId']==user and x['badgeId']==badge and self.valid(x) for x in self.all('holdings'))
    def eligible(self,user,r):
        u=self.get('users',user)
        return not u['disabled'] and not u['isGuest'] and u['profileComplete'] and (not r.get('memberOnly') or (u['memberUntil'] or 0)>now()) and (not r.get('badgeId') or self.owns(user,r['badgeId']))
    def access(self,u,r):
        require(not r.get('badgeId') or self.owns(u['id'],r['badgeId']),'需要有效勋章',403)
        require(not r.get('memberOnly') or (u['memberUntil'] or 0)>now(),'需要有效会员',403)
        require(u['id']==r['ownerId'] or any(x['roomId']==r['id'] and x['userId']==u['id'] and x['status']=='approved' for x in self.all('residents')),'房间需常驻审批后进入',403)
    def manager(self,u,r,owner=False): require(u['role']=='admin' or u['id']==r['ownerId'] or not owner and u['id'] in r['adminIds'],'没有房间管理权限',403)
    def payment_allowed(self,order): return self.development or order.get('paymentProvider')!='development-simulation'
    def sweep(self):
        for r in self.all('rooms'):
            if not self.eligible(r['ownerId'],r):
                candidates=[x for x in r['adminIds'] if self.eligible(x,r)]
                if not candidates:
                    self.delete('rooms',r['id']); self.log('system','room.dissolve',r['id'])
                    for k in ['residents','presence','events']:
                        for x in self.all(k):
                            if x['roomId']==r['id']: self.delete(k,x['id'])
                    continue
                r['ownerId']=candidates[0]; self.log('system','room.transfer',r['id']+':'+candidates[0])
            r['adminIds']=[x for x in r['adminIds'] if x!=r['ownerId'] and self.eligible(x,r)]; self.save('rooms',r)
        for p in self.all('presence'):
            try: self.access(self.get('users',p['userId']),self.get('rooms',p['roomId']))
            except Problem: p['online']=False; self.save('presence',p)
        for u in self.all('users'):
            if u['activeFrameId'] and not any(g['recipientId']==u['id'] and g['frameId']==u['activeFrameId'] and g['status']=='active' and self.payment_allowed(g) and g['expiresAt']>now() for g in self.all('orders')):
                u['activeFrameId']=None; self.save('users',u)
        self.db.execute('DELETE FROM sessions WHERE expires<=?',(now(),))
        for e in self.all('events'):
            if e['at']<now()-300:self.delete('events',e['id'])
    def state(self,u):
        rooms=[r for r in self.all('rooms') if not r['private'] or u['id']==r['ownerId'] or any(x['roomId']==r['id'] and x['userId']==u['id'] and x['status']=='approved' for x in self.all('residents'))]
        ids={r['id'] for r in rooms}; accessible=set()
        for r in rooms:
            try: self.access(u,r); accessible.add(r['id'])
            except Problem: pass
        residents=[r for r in self.all('residents') if r['roomId'] in ids and (r['userId']==u['id'] or any(x['id']==r['roomId'] and (u['id']==x['ownerId'] or u['id'] in x['adminIds']) for x in rooms))]
        presence=[dict(p,online=p['online'] and p['lastSeen']>now()-35) for p in self.all('presence') if p['roomId'] in accessible]
        known={u['id'],*u['friendIds'],*[p['userId'] for p in presence],*[r['userId'] for r in residents]}
        friends=[x for x in self.all('friends') if u['id'] in [x['fromId'],x['toId']]]
        for f in friends: known.update([f['fromId'],f['toId']])
        for r in rooms: known.update([r['ownerId'],*r['adminIds']])
        for b in self.all('badges'): known.add(b['issuerId'])
        for h in self.all('holdings'):
            if h['userId']==u['id'] or self.get('badges',h['badgeId'])['issuerId']==u['id']:known.add(h['userId'])
        for o in self.all('orders'):
            if u['id'] in [o['senderId'],o['recipientId']]:known.update([o['senderId'],o['recipientId']])
        return {'me':u,'users':[dict({k:v for k,v in x.items() if k in ['id','name','avatar','activeFrameId','isGuest','profileComplete']},isMember=(x['memberUntil'] or 0)>now()) for x in self.all('users') if x['id'] in known], 'rooms':rooms,'residents':residents,'presence':presence,'friends':friends,'badges':[b if b['issuerId']==u['id'] else {k:v for k,v in b.items() if k!='code'} for b in self.all('badges')], 'holdings':[h for h in self.all('holdings') if h['userId']==u['id'] or self.get('badges',h['badgeId'])['issuerId']==u['id']], 'orders':[x for x in self.all('orders') if u['id'] in [x['senderId'],x['recipientId']]],'events':[x for x in self.all('events') if x['roomId'] in accessible], 'resources':[x for x in self.all('resources') if x['enabled']], 'development':self.development,'serverTime':now()}
    def action(self,u,d):
        op=text(d,'op'); who=u['id']; result={}
        if op=='profile':
            self.registered(u); u.update(name=text(d,'name'),avatar=text(d,'avatar',40),profileComplete=True); self.save('users',u)
        elif op=='room.create':
            self.registered(u,True)
            r={'id':uid(),'name':text(d,'name'),'ownerId':who,'private':bool(d.get('private',False)),'memberOnly':bool(d.get('memberOnly',False)),'badgeId':d.get('badgeId') or None,'adminIds':[],'background':'library','music':'silent','emojiEnabled':True,'createdAt':now()}
            require(self.eligible(who,r),'没有创建房间资格',403); self.save('rooms',r); result=r
        elif op.startswith('room.'):
            r=self.get('rooms',text(d,'roomId')); rid=r['id']; key=rid+':'+who
            if op=='room.apply':
                self.registered(u); require(not r.get('badgeId') or self.owns(who,r['badgeId']),'需要有效勋章',403)
                existing=next((x for x in self.all('residents') if x['id']==key),None)
                require(not existing or existing['status']!='approved','已经入驻')
                self.save('residents',{'id':key,'roomId':rid,'userId':who,'status':'pending'})
            elif op=='room.review':
                self.manager(u,r,True); x=self.get('residents',rid+':'+text(d,'userId')); require(x['status']=='pending','申请已处理',409)
                require(d.get('status') in ['approved','rejected'],'审批结果无效'); x['status']=d['status']; self.save('residents',x)
            elif op=='room.admins':
                self.manager(u,r,True); ids=d.get('userIds'); require(isinstance(ids,list) and all(isinstance(x,str) for x in ids) and len(ids)==len(set(ids)),'管理员列表无效')
                for x in ids:
                    require(x!=r['ownerId'] and self.eligible(x,r) and self.get('residents',rid+':'+x)['status']=='approved','管理员必须是符合资格的常驻成员')
                r['adminIds']=ids; self.save('rooms',r)
            elif op=='room.settings':
                self.manager(u,r)
                for k,kind in [('background','background'),('music','music')]:
                    if k in d:
                        require(any(x['kind']==kind and x['key']==d[k] and x['enabled'] for x in self.all('resources')),'资源不可用'); r[k]=d[k]
                if 'emojiEnabled' in d: require(type(d['emojiEnabled']) is bool,'表情开关无效'); r['emojiEnabled']=d['emojiEnabled']
                self.save('rooms',r)
            elif op in ['room.enter','room.heartbeat','room.leave']:
                if op!='room.leave':self.access(u,r)
                self.save('presence',{'id':key,'roomId':rid,'userId':who,'online':op!='room.leave','lastSeen':now()})
            elif op=='room.emoji':
                self.access(u,r); p=self.get('presence',key); require(r['emojiEnabled'] and p['online'] and p['lastSeen']>now()-35,'当前不能发送表情',403)
                require(not any(e['userId']==who and e['at']>=now()-1 for e in self.all('events')),'发送过于频繁',429)
                self.save('events',{'id':uid(),'roomId':rid,'userId':who,'emoji':text(d,'emoji',16),'at':now()})
            elif op=='room.delete':
                self.manager(u,r,True); self.delete('rooms',rid)
                for kind in ['residents','presence','events']:
                    for record in self.all(kind):
                        if record['roomId']==rid:self.delete(kind,record['id'])
            else: raise Problem('未知房间操作')
        elif op=='badge.create':
            self.registered(u,True); b={'id':uid(),'issuerId':who,'name':text(d,'name'),'code':secrets.token_urlsafe(16),'expiresAt':expiry(d),'holdingDays':d.get('holdingDays'),'revoked':False}
            expiry(d,'holdingDays'); self.save('badges',b); self.grant(b,who); result=b
        elif op=='badge.redeem':
            self.registered(u); b=next((x for x in self.all('badges') if hmac.compare_digest(x['code'],text(d,'code'))),None)
            require(b and self.valid(b),'兑换码无效或已过期'); require(not any(x['badgeId']==b['id'] and x['userId']==who for x in self.all('holdings')),'已领取，续期需联系发行者'); self.grant(b,who)
        elif op in ['badge.revoke','badge.renew','holding.revoke','holding.renew']:
            b=self.get('badges',text(d,'badgeId')); require(b['issuerId']==who or u['role']=='admin','仅发行者或系统管理员可操作',403)
            obj=b if op.startswith('badge.') else self.get('holdings',b['id']+':'+text(d,'userId'))
            if op.endswith('revoke'):obj['revoked']=True
            else:
                require(not obj['revoked'],'已撤销记录不可续期'); end=expiry(d); obj['expiresAt']=None if end is None else max(now(),obj['expiresAt'] or now())+(end-now())
            self.save('badges' if op.startswith('badge.') else 'holdings',obj)
        elif op=='friend.request':
            self.registered(u); target=self.get('users',text(d,'userId')); require(target['id']!=who and not target['isGuest'] and not target['disabled'],'好友对象无效')
            require(target['id'] not in u['friendIds'],'已是好友'); require(not any(x['status']=='pending' and {x['fromId'],x['toId']}=={who,target['id']} for x in self.all('friends')),'已有申请')
            self.save('friends',{'id':uid(),'fromId':who,'toId':target['id'],'status':'pending'})
        elif op=='friend.review':
            x=self.get('friends',text(d,'id')); require(x['toId']==who and x['status']=='pending','无权处理申请',403); require(d.get('status') in ['accepted','rejected'],'结果无效'); x['status']=d['status']; self.save('friends',x)
            if x['status']=='accepted':
                other=self.get('users',x['fromId']); u['friendIds'].append(other['id']); other['friendIds'].append(who); self.save('users',u); self.save('users',other)
        elif op=='order.create':
            self.registered(u); recipient=self.get('users',text(d,'recipientId')); require(not recipient['isGuest'] and not recipient['disabled'],'收礼人无效')
            resource=self.get('resources','frame-'+text(d,'frameId')); require(resource['enabled'],'头像框已下架')
            o={'id':uid(),'senderId':who,'recipientId':recipient['id'],'frameId':resource['key'],'priceCents':resource['priceCents'],'durationDays':resource['durationDays'],'status':'pending','createdAt':now(),'expiresAt':None,'paymentProvider':None}; self.save('orders',o); result=o
        elif op=='order.pay':
            o=self.get('orders',text(d,'id')); require(o['senderId']==who,'无权支付',403); require(o['status']=='pending','订单状态无效',409)
            require(self.development,'支付提供商尚未配置，订单保持待支付',503); o.update(status='paid',paymentProvider='development-simulation'); self.save('orders',o)
        elif op=='order.accept':
            o=self.get('orders',text(d,'id')); require(o['recipientId']==who and self.payment_allowed(o) and o['status']=='paid','礼物不可领取',403); o.update(status='active',activatedAt=now(),expiresAt=now()+o['durationDays']*86400); self.save('orders',o)
        elif op=='frame.switch':
            id_=d.get('id')
            if id_:
                o=self.get('orders',id_); require(o['recipientId']==who and self.payment_allowed(o) and o['status']=='active' and o['expiresAt']>now(),'头像框未激活或已到期',403); u['activeFrameId']=o['frameId']
            else:u['activeFrameId']=None
            self.save('users',u)
        elif op.startswith('admin.'):
            require(u['role']=='admin','需要后台管理员权限',403)
            if op=='admin.user':
                x=self.get('users',text(d,'userId')); require(x['role']!='admin','不能修改管理员账号')
                if 'disabled' in d:require(type(d['disabled']) is bool,'状态无效'); x['disabled']=d['disabled']
                if 'days' in d:x['memberUntil']=(PERMANENT_MEMBERSHIP_UNTIL if d['days'] is None else expiry(d)) if d['days']!=0 else None
                self.save('users',x)
            elif op=='admin.resource':
                x=self.get('resources',text(d,'id')); x['name']=text(d,'name'); require(type(d.get('enabled')) is bool,'状态无效'); x['enabled']=d['enabled']; url=d.get('url',''); require(isinstance(url,str) and (not url or url.startswith('https://')),'资源 URL 必须为 HTTPS'); x['url']=url
                if x['kind']=='frame':
                    require(type(d.get('priceCents')) is int and 0<d['priceCents']<=1000000,'价格无效'); require(type(d.get('durationDays')) is int and 1<=d['durationDays']<=3650,'期限无效'); x.update(priceCents=d['priceCents'],durationDays=d['durationDays'])
                self.save('resources',x)
            elif op=='admin.order.cancel':
                o=self.get('orders',text(d,'id')); require(o['status']=='pending','仅可取消未支付订单'); o['status']='cancelled'; self.save('orders',o)
            else:raise Problem('未知后台操作')
        else: raise Problem('未知操作')
        if op not in ['room.heartbeat']: self.log(who,op,d.get('roomId') or d.get('id') or d.get('userId') or d.get('badgeId') or result.get('id',''))
        self.sweep(); return result
    def grant(self,b,user): self.save('holdings',{'id':b['id']+':'+user,'badgeId':b['id'],'userId':user,'expiresAt':None if b['holdingDays'] is None else now()+b['holdingDays']*86400,'revoked':False,'claimedAt':now()})
    def request(self,path,d=None,token=''):
        with self.lock, self.db:
            self.sweep()
            if path.startswith('/api/auth/') and d is not None:return self.auth(path.rsplit('/',1)[1],d,token)
            u=self.actor(token)
            if path=='/api/state' and d is None:return self.state(u)
            if path=='/api/action' and d is not None:return self.action(u,d)
            if path=='/api/admin' and d is None:
                require(u['role']=='admin','需要后台管理员权限',403)
                return {**{k:self.all(k) for k in ['users','rooms','residents','badges','holdings','orders','resources']},'audit':[dict(zip(['id','at','actor','action','target'],r)) for r in self.db.execute('SELECT * FROM audit ORDER BY id DESC LIMIT 300')],'development':self.development}
            raise Problem('接口不存在',404)

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):self.handle_request()
    def do_POST(self):self.handle_request()
    def handle_request(self):
        try:
            path=self.path.split('?')[0]
            if not path.startswith('/api/'):
                require(self.command=='GET','Method not allowed',405)
                name={'/':'index.html','/admin':'index.html','/app.js':'app.js','/style.css':'style.css'}.get(path)
                require(name,'Not found',404); data=(ROOT/'static'/name).read_bytes(); self.send_response(200); self.send_header('Content-Type',{'html':'text/html; charset=utf-8','js':'text/javascript; charset=utf-8','css':'text/css'}[name.rsplit('.',1)[1]]); self.end_headers(); self.wfile.write(data); return
            origin=self.headers.get('Origin')
            require(not origin or origin==f'http://{self.headers.get("Host")}' or origin in self.server.allowed_origins,'来源不允许',403)
            size=int(self.headers.get('Content-Length',0)); require(size<=32768,'请求过大',413)
            d=json.loads(self.rfile.read(size)) if self.command=='POST' else None
            require(d is None or isinstance(d,dict),'请求必须是对象')
            if path.startswith('/api/auth/'):
                key=self.client_address[0]; times=self.server.attempts.setdefault(key,[]); times[:]=[x for x in times if x>time.time()-60]; require(len(times)<40,'请求过于频繁',429); times.append(time.time())
            result=self.server.service.request(path,d,self.headers.get('Authorization','').removeprefix('Bearer').strip()); self.respond(200,result)
        except Problem as e:self.respond(e.status,{'error':e.message})
        except (ValueError,TypeError,KeyError):self.respond(400,{'error':'请求格式无效'})
        except Exception:self.respond(500,{'error':'服务内部错误'})
    def do_OPTIONS(self):
        origin=self.headers.get('Origin','')
        if origin not in self.server.allowed_origins:self.respond(403,{'error':'来源不允许'}); return
        self.send_response(204); self.send_header('Access-Control-Allow-Origin',origin); self.send_header('Access-Control-Allow-Headers','Authorization, Content-Type'); self.send_header('Access-Control-Allow-Methods','GET, POST, OPTIONS'); self.end_headers()
    def respond(self,status,data):
        payload=json.dumps(data,ensure_ascii=False).encode(); self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('X-Content-Type-Options','nosniff')
        origin=self.headers.get('Origin','')
        if origin in self.server.allowed_origins:self.send_header('Access-Control-Allow-Origin',origin)
        self.end_headers(); self.wfile.write(payload)

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--port',type=int,default=8080); parser.add_argument('--host',default='127.0.0.1'); parser.add_argument('--db',default=str(ROOT/'study.sqlite')); parser.add_argument('--development',action='store_true'); args=parser.parse_args()
    service=Service(args.db,os.environ.get('STUDY_ADMIN_PASSWORD'),args.development)
    server=ThreadingHTTPServer((args.host,args.port),Handler); server.service=service; server.allowed_origins=os.environ.get('STUDY_ALLOWED_ORIGINS','http://localhost:7357').split(','); server.attempts={}
    def maintain():
        while True:
            time.sleep(5)
            with service.lock,service.db:service.sweep()
    threading.Thread(target=maintain,daemon=True).start(); print(f'Study service http://{args.host}:{args.port} (development payments: {args.development})',flush=True); server.serve_forever()

if __name__=='__main__':main()
