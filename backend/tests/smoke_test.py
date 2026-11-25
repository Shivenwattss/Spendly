"""Local API smoke tests. Uses a temporary SQLite database and never touches spendly.db."""
import os, tempfile, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

fd, db_path = tempfile.mkstemp(suffix='.db')
os.close(fd)
os.environ['DATABASE_URL'] = 'sqlite:///' + db_path
os.environ.pop('OLLAMA_MODEL', None)

from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)
checks = []
def check(name, condition):
    if not condition:
        raise AssertionError(f'FAILED: {name}')
    checks.append(name)

try:
    check('health endpoint', client.get('/health').status_code == 200)
    check('empty transactions', client.get('/transactions').json() == [])
    r = client.post('/transactions', json={'title':'Monthly salary','amount':50000,'type':'income','date':'2026-11-01T09:00:00','category':'Salary'})
    check('create income', r.status_code == 200)
    r = client.post('/transactions', json={'title':'Cafe coffee','amount':500,'type':'expense','date':'2026-11-02T09:00:00'})
    check('create expense and categorise', r.status_code == 200 and r.json()['category'] == 'Food')
    tx = client.get('/transactions').json()
    check('list transactions', len(tx) == 2)
    item_id = tx[0]['id']
    check('update transaction', client.put(f'/transactions/{item_id}', json={'title':'Cafe brunch','amount':650,'type':'expense','date':'2026-11-02T09:00:00'}).status_code == 200)
    csv_data = b'date,description,amount,type,category\n2026-11-03,Metro,60,expense,Travel\n2026-11-04,Freelance,2500,income,Freelance\n'
    r = client.post('/transactions/import-csv', files={'file':('test.csv',csv_data,'text/csv')})
    check('CSV import', r.status_code == 200 and r.json().get('imported') == 2)
    for endpoint in ['/analytics','/insights','/forecast','/anomalies','/recommendations','/financial-health','/goals','/budgets','/recurring','/debts','/planning/summary']:
        r=client.get(endpoint)
        check(f'{endpoint} responds', r.status_code == 200)
    r=client.post('/goals',json={'name':'Laptop','target_amount':80000,'saved_amount':10000})
    check('create savings goal',r.status_code == 200)
    r=client.post('/budgets',json={'category':'Food','monthly_limit':5000})
    check('create budget',r.status_code == 200)
    r=client.post('/recurring',json={'name':'Music subscription','amount':149,'cadence':'monthly','kind':'subscription'})
    check('create recurring tracker',r.status_code == 200)
    r=client.post('/debts',json={'name':'Education loan','outstanding':100000,'monthly_payment':4000,'interest_rate':8.5})
    check('create debt tracker',r.status_code == 200)
    check('Ollama disabled safely',client.post('/assistant/ollama',json={'message':'hello'}).status_code == 503)
    check('rule-based assistant',client.post('/assistant/chat',json={'message':'Where am I spending the most?'}).status_code == 200)
    check('delete transaction',client.delete(f'/transactions/{item_id}').status_code == 200)
    print(f'PASS: {len(checks)} smoke checks')
    for x in checks: print(' -',x)
finally:
    try: os.remove(db_path)
    except OSError: pass
