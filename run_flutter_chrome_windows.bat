@echo off
cd /d "%~dp0flutter_app"
flutter pub get
flutter run -d chrome
