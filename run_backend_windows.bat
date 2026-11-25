@echo off
cd /d "%~dp0backend"
if not exist .venv\Scripts\python.exe py -m venv .venv
call .venv\Scripts\activate.bat
py -m pip install -r requirements.txt
py -m uvicorn app.main:app --reload
