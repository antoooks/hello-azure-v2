@echo off
rem Wrapper for mirror-registry.mjs (Node.js) on Windows. All logic lives in mirror-registry.mjs; run with --help.
where node >nul 2>nul || (
  echo Error: Node.js 18+ is required to run mirror-registry ^(https://nodejs.org^) 1>&2
  exit /b 1
)
node "%~dp0mirror-registry.mjs" %*
