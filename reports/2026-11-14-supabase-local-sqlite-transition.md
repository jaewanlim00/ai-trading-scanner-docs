# Supabase runtime 제거 및 로컬 SQLite 전환 구현 (2026-11-14)

## 목적과 범위

Supabase 기반 로컬 분석 앱을 SQLite 기반 Windows 단일 사용자 앱으로 전환했습니다. 사용자가 승인한 better-sqlite3@12.10.0만 runtime dependency로 추가하고 package manifest/lockfile을 갱신했습니다. 인터넷 공개·다중 사용자·클라우드 DB·자동주문은 추가하지 않았습니다.

Supabase 프로젝트 접속/변경, migration 실행/변경, 외부 배포, .env.local 편집은 하지 않았습니다. Supabase migration 및 preflight 파일은 지시대로 그대로 보존했습니다.

## 변경 파일

### 저장 및 API

- lib/scanner/storage/sqlite.ts: SQLite 초기화, DB 경로, 스키마, run/candidate/task/candle/result 저장 및 조회, owner 검증, idempotency, task lease/retry, atomic candle/result write, run reconciliation.
- lib/scanner/storage/index.ts: API와 캔들 모듈을 위한 저장소 facade.
- lib/scanner/prepare-run.ts: 시장 snapshot/후보 screening 및 run recovery 공통화. screening 중 종료된 run은 사용자가 history에서 재개할 때 다시 준비합니다.
- lib/scanner/candles.ts: Supabase read/upsert를 SQLite cache로 전환. USDT 선형 perpetual 검증과 1h/4h/1d 캔들 재사용은 유지.
- app/api/analysis/start/route.ts, step/route.ts, status/route.ts, results/route.ts: 저장소 facade로 전환.
- 신규 app/api/analysis/history/route.ts: 최근 최대 50개 실행 기록을 소유자 범위로 반환.
- app/api/auth/login/route.ts, lib/scanner/rate-limit.ts, rate-limit-policy.ts, fixed-window-limiter.ts: Supabase limiter를 프로세스 로컬 고정 구간 limiter로 교체하고 기존 한도를 유지.
- lib/scanner/auth.ts: 인증 Origin을 loopback으로 한정하고 Vercel 환경은 fail closed. 로그인 제한의 전달 IP 의존성을 제거.
- 삭제: runtime REST/RPC helper lib/scanner/supabase.ts 및 이전 limiter lib/scanner/local-login-limiter.ts.
- app/page.tsx: 기존 분석 UI를 유지하면서 저장된 기록 불러오기와 미완료 실행 이어가기 UI를 추가. 이어가기는 사용자가 선택한 경우에만 실행됩니다.

### 실행, 저장 파일, 문서, 테스트

- package.json, package-lock.json: 승인된 better-sqlite3@12.10.0, test script, loopback 한정 dev/start script를 반영했습니다. npm install script 허용은 해당 package/version 하나로 고정했습니다.
- next.config.ts: native module 외부화와 dev 산출물 .next-dev 분리를 반영했습니다. 기존 Turbopack root 설정은 보존했습니다.
- .gitignore: data/, .codex-checkpoints/, .next-dev/를 추가해 DB, WAL/SHM, 백업 및 체크포인트가 Git에 포함되지 않게 했습니다.
- eslint.config.mjs, tsconfig.json: dev build/DB/checkpoint 산출물 제외와 별도 dev type 경로.
- README.md: Windows 실행, 인증 환경변수 이름, DB 백업·복원·PC 이동 방법.
- 신규 tests/scanner-storage.test.mjs, tests/local-storage-auth.test.mjs, tests/register-server-only-loader.mjs. 기존 tests/scanner-security.test.mjs는 로컬 limiter 정책을 반영해 갱신했습니다.

작업 전 사용자 변경 파일과 미추적 source를 .codex-checkpoints/pre-sqlite-20261114/에 복사했습니다. .env.local, node_modules, .next, data는 체크포인트에서 제외했습니다.

## SQLite 저장 구조

파일: data/scanner.sqlite (첫 analysis history 조회/저장 때 자동 생성).

- scanner_runs: 상태, settings, 거래소 상태, 시장/후보/task 집계, 실행 시각, idempotency key, 단일 local owner.
- scanner_candidates: screening snapshot, 점수, 선택/제외 근거와 상태.
- scanner_tasks: queued/processing/retry_wait/completed/failed, attempts, max attempts, retry 시각, lease token.
- scanner_candles: exchange+symbol+timeframe+timestamp 복합 primary key, OHLCV, is_closed, fetched_at.
- scanner_results: run/candidate/side/algorithm 버전 단위 unique 결과; 롱·숏 별도 저장.

외래 키, 조회 인덱스, WAL, busy timeout을 적용했습니다. 캔들/result 저장과 task 완료는 단일 SQLite transaction입니다. 실행 이력은 재시작 후에도 남습니다. DB/backup/WAL/SHM은 Git ignore 대상입니다.

### 초기화, 백업, 복원

- DB는 CREATE TABLE IF NOT EXISTS 방식으로 자동 초기화합니다. DB를 지우거나 초기화하는 명령은 만들지 않았습니다.
- 백업·복원은 앱 정상 종료 후 SQLite 파일을 복사하는 Windows PowerShell 절차를 README에 문서화했습니다. 복원 전 기존 파일을 timestamp backup으로 보존하도록 안내합니다.
- 다른 Windows PC 이동은 앱 종료 후 data\scanner.sqlite 복사, Node.js 26.x x64 설치, .env.local 안전 설정, npm.cmd install 및 npm.cmd run dev 순서입니다.
- 별도 PC 이동이나 수동 backup/restore 실행은 하지 않았습니다.

## 인증, 세션, 요청 제한

- 비밀번호 검증, HMAC 서명 8시간 세션, HttpOnly/SameSite=Strict 쿠키, 만료, POST Origin 검증을 유지했습니다.
- 허용 Origin과 요청은 loopback host만 허용하고 alias는 같은 scheme/port일 때만 인정합니다. Vercel 환경은 인증 설정 오류로 중단합니다.
- npm.cmd run dev 및 npm.cmd run start는 기본 127.0.0.1에 바인딩합니다.
- 기존 한도 유지: login 5/15분, start 3/10분, step 240/30분, status 320/30분, results 60/10분, markets 4/분.
- limiter는 프로세스 메모리 방식이므로 서버 재시작 때 카운터가 초기화되고 여러 프로세스 간 공유되지 않습니다.
- SCANNER_LOGIN_PASSWORD, SCANNER_SESSION_SECRET, SCANNER_ALLOWED_ORIGIN은 계속 필요합니다. Supabase 환경변수는 활성 앱 코드에서 참조하지 않습니다. 기존 .env.local은 읽어서 값을 출력하거나 수정하지 않았으며, 과거 Supabase 변수가 남아도 앱에서는 사용하지 않습니다.

## 검증 결과

### 코드·단위 검증

- 기준(수정 전): 기존 테스트 9/9, lint exit 0, build exit 0.
- npm.cmd test: exit 0, 12/12. SQLite transaction, stale lease 거부, idempotent start, candle upsert, 롱·숏 결과 저장, 별도 프로세스 재오픈 후 지속성, owner mismatch, local Origin 및 Supabase 설정 없이 local limiter 동작을 확인했습니다.
- npm.cmd run lint: exit 0, warnings 0.
- npx.cmd tsc --noEmit: exit 0.
- npm.cmd run build: exit 0. Next.js 15.5.29 production build와 history route 생성 확인.

### 실제 localhost API 검증

개발 서버는 127.0.0.1:3000에만 실행했습니다. 서버 프로세스에 Supabase URL/service role 변수를 빈 값으로 지정했습니다. 인증 비밀값은 출력하거나 문서에 기록하지 않았습니다.

- Login 성공.
- GET /api/analysis/history: 최초 0개.
- POST /api/analysis/start: queued, 전체 시장 2,107, Binance 758 / OKX 528 / Bybit 821, 1차 통과 1,156, 정밀 분석 후보 1개.
- POST /api/analysis/step: 완료. 실제 공개 OHLCV 수집 및 분석 task 1건 성공.
- GET /api/analysis/status: completed, 진행률 100%, completed 1, failed 0.
- SQLite 실제 저장: 1h candle 501개, 4h 501개, 1d 415개. 롱/숏 결과 각각 1개가 저장됐고 둘 다 qualified=false. 따라서 이번 실행의 /api/analysis/results qualified 결과는 0개입니다. 샘플이 설정 점수 기준을 넘지 않은 결과입니다.
- GET /api/analysis/results 성공, count 0.
- 서버 종료 후 다시 실행한 뒤 로그인 성공, history 1개에 해당 run 존재, 이전 status/results 조회 성공.
- 별도 GET /api/markets: HTTP 200, 2,107개, 거래소별 758/528/821, 가격 누락 0, 오류 0, total 705.2ms. BTC/ETH 심볼 확인.
- app/ 및 lib/ 전체 검색에서 Supabase REST/RPC helper, URL/key, /rest/v1 참조 0건.
- 전체 2,107개 OHLCV는 요청하지 않고 분석 후보 1개만 수집했습니다.
- 개발 서버는 테스트 후 종료했습니다. data/scanner.sqlite에는 완료된 run과 candles/results가 남아 있습니다.

## 오류와 조치

첫 패키지 설치는 sandbox registry 요청 EACCES로 실패했습니다. 승인된 install 명령을 네트워크 권한으로 재실행해 설치했습니다. npm이 native install script를 차단해 better-sqlite3@12.10.0 단일 버전의 script만 allowScripts로 승인한 뒤 Windows x64 바이너리를 rebuild했습니다.

첫 dev API 요청은 Turbopack native package chunk 누락으로 실패했습니다. Next 설정에서 native module 외부화를 명시하고 dev build dir을 분리한 뒤 전체 API E2E를 통과했습니다.

npm install 출력에 moderate audit advisories 6건이 있었습니다. npm audit fix/강제 업그레이드는 하지 않았습니다. pre-change checkpoint와 비교 시 lockfile은 기존 441개 항목을 유지하고 35개를 추가했으며 기존 package version 변경/삭제는 0건입니다.

## 잔여 제한 및 다음 단계

- local limiter 카운터는 server restart 시 초기화되고 process 간 공유되지 않습니다. 한 번에 하나의 loopback 서버를 실행하는 사용 구조를 전제로 합니다.
- 실제 샘플의 롱·숏 qualified 후보는 0개였습니다. pipeline 완료와 매매 신호 생성은 별개입니다.
- SQLite 파일은 이 PC에서 생성/재시작 유지가 확인됐고 타 PC 이동 및 수동 백업/복원은 미검증입니다.
- Supabase migration 00100/00200, preflight SQL은 변경·실행하지 않았고 기존 Supabase project도 열지 않았습니다.
- .env.local을 변경하지 않았으며, 기존 Supabase 변수 설정 여부/값은 조사하거나 보고하지 않았습니다.
- instructions/WORKFLOW.md와 충돌하는 변경은 없습니다. 해당 규칙 문서는 수정하지 않았습니다.

## Windows 실행 명령

프로젝트 폴더에서:

```powershell
cd C:\Users\PC1\ai-trading-scanner
npm.cmd install
npm.cmd run dev
```

브라우저: http://localhost:3000. Production 로컬 실행은 npm.cmd run build 후 npm.cmd run start입니다. 백업·복원·PC 이동 절차는 코드 프로젝트 README의 로컬 저장소 항목을 따릅니다.
