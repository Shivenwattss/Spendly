# Spendly — consolidated development build

This is a clean, consolidated Flutter + FastAPI project based on the previous Spendly builds. It is intended for local development and testing on Windows + Chrome.

## Included

- Flutter dashboard, activity, budgets, analytics and profile tabs
- Add, edit and delete transactions
- CSV transaction import with rule-based merchant categorisation
- Search/filter activity
- Monthly analytics and category breakdowns
- Smart insights, statistical outlier detection, and month-end expense estimate
- Rule-based financial recommendations
- Financial health indicator (transparent 0–100 educational indicator)
- Savings goals and progress estimates
- Category budgets, recurring-payment trackers, and debt/EMI trackers
- Rule-based financial assistant
- Optional Ollama endpoint (off unless `OLLAMA_MODEL` is configured)
- SQLite persistence
- Backend smoke-test script

## Requirements

- Python 3.10+
- Flutter stable with Dart 3.4+
- Google Chrome
- Windows PowerShell or Command Prompt

## Start on Windows

Open Terminal 1 at the extracted `spendly_project` root:

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

If PowerShell blocks activation, use Command Prompt and run `.venv\Scripts\activate.bat`.

Open Terminal 2 at the project root:

```powershell
cd flutter_app
flutter pub get
flutter run -d chrome
```

Keep the backend terminal running. API health: http://127.0.0.1:8000/health. API docs: http://127.0.0.1:8000/docs.

Two optional helper scripts are included at the project root: `run_backend_windows.bat` and `run_flutter_chrome_windows.bat`. Run them from File Explorer or a terminal after Python/Flutter are installed.

## Test the backend

From `backend` after installing requirements:

```powershell
python tests/smoke_test.py
```

The test uses a temporary database and checks transaction CRUD, CSV import, analytics, insights, forecasting, anomaly detection, recommendations, financial health, planning endpoints, and assistant modes. It does not modify `spendly.db`.

## CSV format

Required columns: `date,description,amount,type`. Optional: `category`.

- Date: `YYYY-MM-DD` or ISO datetime
- Type: `income` or `expense`
- Amount: positive number

A sample file is at `backend/sample_transactions.csv`.

## Database and preserving your data

The backend creates `backend/spendly.db` automatically when run from the `backend` directory. This ZIP deliberately does not include a database file. To preserve data from an earlier project, stop the backend and copy your old `backend/spendly.db` into this build's `backend` folder before starting it. Keep a separate backup copy. Existing schema changes are not handled by a formal migration system yet; test with a copy first.

## Optional Ollama setup

Ollama is optional and OFF by default. Install Ollama separately, then in a PowerShell backend terminal:

```powershell
ollama pull llama3.2
$env:OLLAMA_MODEL='llama3.2'
$env:OLLAMA_URL='http://127.0.0.1:11434/api/generate'
uvicorn app.main:app --reload
```

Restart the backend after setting environment variables. The assistant's Ollama switch calls the local endpoint. Ollama must be reachable from the computer running FastAPI. Do not expose the Ollama endpoint publicly. The local LLM receives a compact summary of recent transaction data and the question; do not use sensitive real financial data until proper user isolation and security are implemented.

## API address

For Flutter Web running in Chrome on the same PC, `http://127.0.0.1:8000` is configured. Android emulator typically needs `http://10.0.2.2:8000`; a physical device needs the PC's LAN IP and firewall/network configuration. iOS builds require macOS and Xcode.

## Important limitations — not production-ready

This is a local development build, not a regulated or production-ready fintech product. The following remain genuinely outstanding:

1. User registration/login, per-user data isolation and role/permission model.
2. Production security: authentication, encryption/key management, rate limiting, audit logging, secure CORS, secrets management and security review.
3. PostgreSQL deployment, migrations, backups, monitoring and cloud hosting.
4. Actual bank Account Aggregator integration. This requires an eligible regulated FIU/provider arrangement, consent flows, compliance and provider credentials. No bank sync is included.
5. Direct personal Paytm transaction-history integration is not included. Do not assume merchant gateway APIs provide personal account history.
6. ML models are not trained. Forecasting and anomaly detection are statistical baselines; categories/recommendations are rule-based.
7. Recurring payments are manually entered trackers, not automatic bank-debit detection.
8. Ollama is optional local inference, not a hosted multi-user LLM service. Chat history is not persisted as long-term conversational memory.
9. Flutter compilation has not been run in this packaging environment; verify with `flutter pub get` and `flutter run -d chrome` on your PC.

Use synthetic/test financial data only until authentication, isolation, security and compliance work is complete. The financial health indicator is an educational summary of recorded data, not a credit score or professional financial advice.
