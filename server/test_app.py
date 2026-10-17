import tempfile
import unittest
from app import Service, Problem, now

class ServiceTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.path=self.tmp.name+'/test.db'; self.s=Service(self.path,'administrator-test-password',True)
        self.admin=self.s.request('/api/auth/login',{'login':'admin','password':'administrator-test-password'})['token']
        self.a,self.au=self.user('alice'); self.b,self.bu=self.user('bruce'); self.c,self.cu=self.user('chloe')
    def tearDown(self):self.s.db.close();self.tmp.cleanup()
    def user(self,name):
        token=self.s.request('/api/auth/register',{'login':name,'password':'long-password','name':name})['token'];self.act(token,'profile',name=name,avatar='学');return token,self.state(token)['me']['id']
    def act(self,t,op,**kw):return self.s.request('/api/action',{'op':op,**kw},t)
    def state(self,t):return self.s.request('/api/state',token=t)
    def test_auth_upgrade_and_no_impersonation(self):
        t=self.s.request('/api/auth/guest',{})['token']; id_=self.state(t)['me']['id']
        with self.assertRaises(Problem):self.act(t,'room.create',name='no')
        nt=self.s.request('/api/auth/register',{'name':'Guest upgraded','login':'guest','password':'long-password'},t)['token']
        self.assertEqual(id_,self.state(nt)['me']['id'])
        with self.assertRaises(Problem):self.state(t)
        with self.assertRaises(Problem):self.s.request('/api/admin',token=self.a)
        with self.assertRaises(Problem):self.act(self.a,'admin.user',userId=self.bu,days=30)
        with self.assertRaises(Problem):self.s.request('/api/state',{'users':[]},self.a)
    def test_private_room_approval_presence_and_emoji(self):
        r=self.act(self.a,'room.create',name='quiet',private=True)
        with self.assertRaises(Problem):self.act(self.b,'room.enter',roomId=r['id'])
        self.assertEqual([],self.state(self.b)['rooms'])
        self.act(self.b,'room.apply',roomId=r['id'])
        with self.assertRaises(Problem):self.act(self.c,'room.review',roomId=r['id'],userId=self.bu,status='approved')
        self.act(self.a,'room.review',roomId=r['id'],userId=self.bu,status='rejected')
        for key in ['rooms','residents','presence','events']:
            self.assertEqual([],self.state(self.b)[key])
        self.act(self.b,'room.apply',roomId=r['id']);self.act(self.a,'room.review',roomId=r['id'],userId=self.bu,status='approved')
        self.act(self.b,'room.enter',roomId=r['id']);self.act(self.b,'room.emoji',roomId=r['id'],emoji='赞')
        self.assertEqual(1,len(self.state(self.a)['events']))
        self.act(self.a,'room.settings',roomId=r['id'],emojiEnabled=False)
        with self.assertRaises(Problem):self.act(self.b,'room.emoji',roomId=r['id'],emoji='赞')
        self.act(self.b,'room.leave',roomId=r['id']);self.assertFalse(self.state(self.a)['presence'][0]['online'])
    def test_individual_badge_expiry_succession_and_dissolution(self):
        badge=self.act(self.a,'badge.create',name='club',days=30,holdingDays=7)
        for t in [self.b,self.c]:self.act(t,'badge.redeem',code=badge['code'])
        room=self.act(self.a,'room.create',name='club room',badgeId=badge['id'])
        for t,u in [(self.b,self.bu),(self.c,self.cu)]:
            self.act(t,'room.apply',roomId=room['id']);self.act(self.a,'room.review',roomId=room['id'],userId=u,status='approved')
        self.act(self.a,'room.admins',roomId=room['id'],userIds=[self.cu,self.bu])
        self.act(self.a,'holding.revoke',badgeId=badge['id'],userId=self.au)
        self.assertEqual(self.cu,self.s.get('rooms',room['id'])['ownerId'])
        self.act(self.a,'holding.renew',badgeId=badge['id'],userId=self.bu,days=10)
        self.assertGreater(self.s.get('holdings',badge['id']+':'+self.bu)['expiresAt'],self.s.get('holdings',badge['id']+':'+self.cu)['expiresAt'])
        self.act(self.a,'badge.revoke',badgeId=badge['id']);self.assertEqual([],self.s.all('rooms'))
    def test_membership_expiry_and_ordered_transfer(self):
        self.act(self.admin,'admin.user',userId=self.au,days=1)
        room=self.act(self.a,'room.create',name='members',memberOnly=True)
        self.act(self.admin,'admin.user',userId=self.au,days=0)
        self.assertEqual([],self.s.all('rooms'))
        self.assertTrue(any(x[0]=='room.dissolve' for x in self.s.db.execute('SELECT action FROM audit')))
    def test_public_rooms_require_approved_residency(self):
        r=self.act(self.a,'room.create',name='public')
        guest=self.s.request('/api/auth/guest',{})['token']
        for t in [self.b,guest]:
            for op in ['room.enter','room.heartbeat','room.emoji']:
                with self.assertRaises(Problem):self.act(t,op,roomId=r['id'],emoji='赞')
        private=self.act(self.a,'room.create',name='private',private=True)
        self.act(self.b,'room.apply',roomId=private['id'])
        self.assertNotIn(private['id'],[x['id'] for x in self.state(self.b)['rooms']])
        self.act(self.a,'room.review',roomId=private['id'],userId=self.bu,status='rejected')
        self.assertNotIn(private['id'],[x['id'] for x in self.state(self.b)['rooms']])
    def test_reserved_admin_and_development_entitlements_on_restart(self):
        with self.assertRaises(Problem):self.s.request('/api/auth/register',{'login':'ADMIN','name':'bad','password':'long-password'})
        orders=[self.act(self.a,'order.create',recipientId=self.bu,frameId='starlight') for _ in range(2)]
        for o in orders:self.act(self.a,'order.pay',id=o['id'])
        self.act(self.b,'order.accept',id=orders[0]['id']);self.act(self.b,'frame.switch',id=orders[0]['id'])
        prod=Service(self.path,development=False)
        self.assertIsNone(prod.request('/api/state',token=self.b)['me']['activeFrameId'])
        for op,o in [('order.accept',orders[1]),('frame.switch',orders[0])]:
            with self.assertRaises(Problem):prod.request('/api/action',{'op':op,'id':o['id']},self.b)
        prod.db.close()
    def test_permanent_membership_and_room_cleanup(self):
        self.act(self.admin,'admin.user',userId=self.au,days=None)
        self.assertGreater(self.state(self.a)['me']['memberUntil'],now()+100*365*86400)
        self.assertTrue(next(x for x in self.state(self.a)['users'] if x['id']==self.au)['isMember'])
        reopened=Service(self.path)
        reopened.request('/api/state',token=self.a)
        self.assertGreater(reopened.get('users',self.au)['memberUntil'],now())
        reopened.db.close()
        room=self.act(self.a,'room.create',name='permanent members',memberOnly=True)
        self.act(self.admin,'admin.user',userId=self.bu,days=30)
        self.act(self.b,'room.apply',roomId=room['id']);self.act(self.a,'room.review',roomId=room['id'],userId=self.bu,status='approved')
        self.act(self.b,'room.enter',roomId=room['id']);self.act(self.b,'room.emoji',roomId=room['id'],emoji='赞')
        self.act(self.a,'room.delete',roomId=room['id'])
        for kind in ['rooms','residents','presence','events']:self.assertEqual([],self.s.all(kind))
    def test_friends_accept_and_decline(self):
        self.act(self.a,'friend.request',userId=self.bu);r=self.state(self.b)['friends'][0]
        with self.assertRaises(Problem):self.act(self.c,'friend.review',id=r['id'],status='accepted')
        self.act(self.b,'friend.review',id=r['id'],status='rejected');self.act(self.a,'friend.request',userId=self.bu)
        r=next(x for x in self.state(self.b)['friends'] if x['status']=='pending');self.act(self.b,'friend.review',id=r['id'],status='accepted')
        self.assertIn(self.au,self.state(self.b)['me']['friendIds']);self.assertIn(self.bu,self.state(self.a)['me']['friendIds'])
    def test_orders_payment_isolation_acceptance_and_expiry(self):
        o=self.act(self.a,'order.create',recipientId=self.bu,frameId='starlight',priceCents=1)
        self.assertEqual(600,o['priceCents'])
        with self.assertRaises(Problem):self.act(self.b,'order.accept',id=o['id'])
        self.s.development=False
        with self.assertRaises(Problem):self.act(self.a,'order.pay',id=o['id'])
        self.assertEqual('pending',self.s.get('orders',o['id'])['status']);self.s.development=True
        self.act(self.a,'order.pay',id=o['id'])
        with self.assertRaises(Problem):self.act(self.c,'order.accept',id=o['id'])
        self.act(self.b,'order.accept',id=o['id']);self.act(self.b,'frame.switch',id=o['id'])
        self.assertEqual('starlight',self.state(self.b)['me']['activeFrameId'])
        o=self.s.get('orders',o['id']);o['expiresAt']=now()-1
        with self.s.db:self.s.save('orders',o)
        self.assertIsNone(self.state(self.b)['me']['activeFrameId'])
    def test_persistence_resources_audit_and_session_revocation(self):
        self.act(self.admin,'admin.resource',id='music-rain',name='Rain',url='https://example.com/rain.mp3',enabled=True)
        other=Service(self.path);self.assertEqual('Rain',other.get('resources','music-rain')['name']);self.assertEqual(self.au,other.request('/api/state',token=self.a)['me']['id']);other.db.close()
        self.assertGreater(len(self.s.request('/api/admin',token=self.admin)['audit']),0)
        self.act(self.admin,'admin.user',userId=self.bu,disabled=True)
        with self.assertRaises(Problem):self.state(self.b)
        self.s.request('/api/auth/logout',{},self.a)
        with self.assertRaises(Problem):self.state(self.a)

class HTTPTest(ServiceTest):
    """Repeat business regressions through a real HTTP socket and JSON boundary."""
    def setUp(self):
        super().setUp()
        from app import Handler, ThreadingHTTPServer
        import threading
        self.http=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.http.service=self.s;self.http.allowed_origins=['http://localhost:7357'];self.http.attempts={}
        self.thread=threading.Thread(target=self.http.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):
        self.http.shutdown();self.http.server_close();self.thread.join();super().tearDown()
    def http_request(self,path,data=None,token='',headers=None):
        import json
        from urllib.request import Request,urlopen
        from urllib.error import HTTPError
        req=Request('http://127.0.0.1:'+str(self.http.server_port)+path,
                    data=None if data is None else json.dumps(data).encode(),
                    headers={'Authorization':'Bearer '+token,'Content-Type':'application/json',**(headers or {})})
        try:
            with urlopen(req) as response:return json.load(response)
        except HTTPError as e:raise Problem(json.load(e)['error'],e.code)
    def act(self,t,op,**kw):
        if not hasattr(self,'http'):return super().act(t,op,**kw)
        return self.http_request('/api/action',{'op':op,**kw},t)
    def state(self,t):
        if not hasattr(self,'http'):return super().state(t)
        return self.http_request('/api/state',token=t)
    def test_http_auth_origin_and_admin_boundary(self):
        login=self.http_request('/api/auth/login',{'login':'admin','password':'administrator-test-password'})
        self.assertIn('audit',self.http_request('/api/admin',token=login['token']))
        for path,token,headers,status in [('/api/state','',{},401),('/api/admin',self.a,{},403),('/api/state',self.a,{'Origin':'https://untrusted.example'},403)]:
            with self.assertRaises(Problem) as error:self.http_request(path,token=token,headers=headers)
            self.assertEqual(status,error.exception.status)
        self.http_request('/api/auth/logout',{},login['token'])
        with self.assertRaises(Problem):self.http_request('/api/admin',token=login['token'])

if __name__=='__main__':unittest.main()
