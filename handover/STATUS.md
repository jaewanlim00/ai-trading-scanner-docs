# 프로젝트 진행 상태

**기준일:** 2026-11-14
**코드 프로젝트:** `C:\Users\PC1\ai-trading-scanner`
**코드 저장소:** 현재 작업 기록 기준, 문서 저장소와 별도 관리

## 현재 단계

수동 실행형 탐색기의 분석 흐름, 화면/API 및 단일 사용자 인증·run owner·호출 제한·task 복구 구현과 신규 migration 정적 검토가 완료됐습니다. Read-only preflight SQL을 준비했지만 원격 DB에는 접속하지 않았고 migration도 적용하지 않았습니다. 실제 Supabase 환경 설정과 영속 저장 end-to-end 검증은 미완료입니다. 최신 구현/검토 보고서가 이 파일의 과거 상태 설명보다 우선합니다.

## 구현 및 확인된 기능

- `/api/markets`: Binance 758개, OKX 528개, Bybit 821개, 총 2,107개 USDT 선형 무기한 시장을 반환
- Coin-M, inverse, spot, option 제외 필터와 거래소별 병렬 bulk ticker 조회 유지
- 후보 선정: 거래대금, 24시간 변동률, 고저폭 및 고저점 접근도를 이용한 추세 추종/변곡 탐색
- 후보별 선정·제외 근거 기록, 최대 분석 수와 상대 백분위 등 실행 설정 제공
- 후보에 대해 1h·4h·1d 캔들을 묶음으로 수집하고 저장된 캔들을 재사용·갱신
- 종료 캔들 기준 RSI, 추세 구조, 추세선 이탈, 고점·저점 지표 계산
- 롱·숏 결과 별도 저장 및 화면 표시
- 분석 시작, step, status, results API 구성. 시작 API는 Supabase 설정이 없으면 시장 호출 전에 중단
- Supabase 스키마와 task claim RPC SQL 작성: `supabase/migrations/20261114000100_scanner.sql`

## 이전 시장/API 검증 결과 (보안 적용 전 기록)

- `npm.cmd run build`: 종료 코드 0
- Production 서버의 `/api/markets`: HTTP 200, 2,107개 반환, 거래소별 758/528/821개, 누락 가격 0
- 반환 시장 USDT 선형 필터 위반: 0
- BTC/ETH 가격: 세 거래소 모두 확인
- 메인 화면: HTTP 200, 분석 시작 버튼 표시. 초기 화면에 자동 시장 API 호출 없음
- Supabase가 미설정된 상태의 `/api/analysis/start`: HTTP 503으로 안전하게 중단
- CCXT 공개 OHLCV 호출 방식으로 3개 거래소 × 1h/4h/1d에서 500개 조회를 확인한 기록이 있음. 다만 현 코드의 DB 캐시/저장 통합은 실제 Supabase에서 검증되지 않음
- 문서 저장소 작업에서는 코드 빌드를 실행하지 않음. 위 빌드 결과는 직전 코드 작업 결과임

## 미완료 / 주의 사항

1. 신규 migration 정적 검토와 read-only preflight SQL 작성은 완료됐습니다. 대상 Supabase의 실제 read-only preflight 및 migration 적용은 별도 승인/실행 단계가 필요합니다.
2. `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`를 승인된 로컬/Vercel 비밀 환경변수에 설정해야 합니다. 비밀값을 Git에 저장하지 않습니다.
3. Supabase 연결 후 `maxCandidates=1` 등 작은 규모로 start → step → status → results, 캔들 저장, 중복 upsert를 end-to-end 확인해야 합니다.
4. 앱 단일 사용자 인증은 구현됐습니다. Vercel 보호 설정은 미구성 상태이며 공개 배포 전에 별도로 검토/승인해야 합니다.
5. 원형파·후잔잔의 상세 판정 규칙은 미정입니다. 사용자 확정 규칙을 받은 뒤에만 신호 로직에 반영합니다.
6. 후보 거래량 변화는 1h 캔들로 확인하는 후속 지표이며, 24h ticker만으로 계산하지 않습니다.

## 다음 작업 순서

1. Dashboard에서 전용 scanner Supabase project를 확인한 뒤 승인된 read-only role로 preflight SQL 결과를 확인
2. 모든 conditional blocker와 owner-less legacy run의 처리 방식을 검토
3. 별도 승인 후 atomic migration 적용과 승인된 secret store의 환경변수 provisioning
4. staging에서 단일 후보 E2E, 중복 start, owner isolation, limiter 동시성 및 task lease/retry 확인
5. Vercel 보호 설정과 배포는 별도 승인 후 진행
6. 확정된 파동 규칙을 `decisions/`에 기록한 후 선택적으로 구현

기존 변경사항을 보존하며, 데이터베이스·환경변수·외부 서비스 변경은 사전 승인 후 진행합니다.
## Supabase 준비 상태 검토 (2026-11-14)

읽기 전용 검토 보고서: `reports/2026-11-14-supabase-readiness-review.md`.

- migration 및 코드 구조 검토와 빌드는 완료됐습니다. migration 적용 및 DB end-to-end 검증은 하지 않았습니다.
- 빌드: `npm.cmd run build` escalation 실행 종료 코드 0. 첫 sandbox 실행은 Turbopack의 상위 폴더 접근 거부로 실패했습니다.
- 코드 프로젝트 `master`의 기존 변경 파일은 작업 전후 동일합니다. 코드, 환경변수, 원격 DB, 배포는 이 단계에서 변경하지 않았습니다.
- High 위험: 분석 API 네 route 모두 인증/소유권/rate-limit이 없고, migration은 기존 동명 객체·정책을 확인하지 않습니다. 공개 배포 금지, migration은 전용 빈 DB 확인 전 적용 금지.
- High 위험: 2분 lease 만료 후 task 재claim에 최대 attempts가 없습니다. step은 60초 제한, CCXT fetch는 3회 retry지만 crash 재claim은 제한되지 않습니다.
- Medium 위험: SECURITY DEFINER의 search_path가 public 단독, 기존 정책/grant 검사 없음, run 생성이 multi-request라 부분 기록이 남을 수 있습니다.
- Supabase 환경변수 미설정, `.env.local` 없음. 원격 DB, effective role/RLS, migration 성공, 실제 upsert/lease 복구는 미검증입니다.

### 다음 진행 순서

1. 인증·소유권·호출 제한 개선 코드 작업 승인 및 적용
2. 전용 Supabase 프로젝트와 migration 적용 대상 승인
3. migration preflight에서 기존 객체·정책·grant·함수 owner를 read-only 확인
4. 환경변수 설정 승인 후 비밀 저장소에만 등록
5. staging에서 단일 후보 end-to-end, 중복 upsert, 동시 claim 및 failure recovery 검증
6. 접근 제한 및 Vercel maxDuration/lease 확인 뒤 별도 배포 승인

검토 상세의 심각도와 적용 전 절차는 위 보고서를 기준으로 합니다.

## API 보안 및 작업 복구 설계 검토 완료 (2026-11-14)

설계 보고서: reports/2026-11-14-api-security-recovery-design.md.

- 읽기 전용 설계 분석만 완료했습니다. 코드, SQL, 원격 DB, 환경변수, 패키지, Vercel 설정, 배포는 변경하지 않았습니다.
- 현재 네 분석 API에 인증 및 run owner 검사가 없습니다. service role은 RLS를 우회하므로 route와 claim RPC에서 owner 확인이 필요합니다.
- 단일 사용자 권고: 새 패키지/IdP 없이 앱 단일 비밀번호 로그인과 HMAC 서명 HttpOnly session. Vercel Deployment Protection/WAF는 플랜과 적용 범위를 확인한 뒤 보조 경계로 사용합니다.
- 서버리스 limiter는 Vercel WAF의 IP/path 제한과 Supabase 원자 RPC의 principal/run 제한을 조합합니다. 인스턴스 메모리 방식은 사용하지 않습니다.
- task attempts 상한, 일시/영구 오류 분류, retry_wait, lease fencing, dead-letter/manual retry를 설계했습니다.
- 실패 task가 포함된 run도 completed가 되는 현재 상태 계산과 start 과정의 부분 DB 기록 가능성을 확인했습니다.
- 실제 Vercel 플랜/보호 범위, Supabase 스키마·권한, DB rate limit 동시성은 미검증입니다. 구현은 별도 승인을 기다립니다.

### 다음 단계

1. 사용자가 권고 인증 방식과 구현 범위를 승인
2. 인증·owner·rate-limit 코드 설계 구현
3. owner, limiter, retry 및 run reconciliation을 위한 새 migration 설계 후 schema 변경 승인
4. 환경변수 provisioning 및 Vercel protection/WAF 설정 승인
5. staging에서 미인증 차단, IDOR, 다중 인스턴스 limit, task recovery 검증
6. 검증 후 배포 별도 승인



## 다음 구현 단계 승인 및 지시서 발행 (2026-11-14)

사용자가 다음 범위를 승인했습니다. GPT Work 작업 지시서: `instructions/04-auth-owner-retry-implementation.md`.

승인된 범위:
- 단일 사용자 로그인/서명 세션 및 로그인 UI
- 분석 API와 market API 인증, run owner 검사
- DB 기반 호출 제한 및 중복 start 방지 코드
- task 재시도 상한, lease fencing, run 상태 정산 코드
- 신규 forward migration SQL 파일 작성
- 빌드/테스트, 구현 보고서 및 handover 갱신

이번 승인에 포함되지 않은 항목:
- 실제 Supabase DB에 migration 적용 또는 원격 DB 변경
- 비밀값 생성·등록 및 환경변수 파일 변경
- Vercel/WAF/Deployment Protection 설정
- 외부 서비스 설정, 배포, 패키지 설치/버전 변경
- 자동주문 또는 자동 감시

GPT Work는 작업 전 현재 Git 상태와 기존 사용자 변경을 확인·보존해야 합니다. 구현 후 빌드/테스트 결과와 미실행된 DB 검증을 구분해 보고해야 합니다.


## 인증·소유권·작업 복구 구현 완료 (2026-11-14)

구현 보고서: `reports/2026-11-14-auth-owner-retry-implementation.md`. 이 절이 이 파일의 과거 보안 분석/미완료 상태보다 최신 기준입니다.

- 단일 비밀번호 + HMAC-SHA256 8시간 세션 로그인, HttpOnly/SameSite=Strict 쿠키, production Secure, canonical Origin 확인을 추가했습니다. 민감한 API 응답은 no-store로 반환합니다.
- `/api/analysis/start|step|status|results`와 `/api/markets`를 인증으로 보호했습니다. run owner를 DB 조회와 claim RPC에 적용해 타 run은 404로 처리합니다.
- DB 원자 limiter는 로그인 5/15분, start 3/10분, step 240/30분, status 320/30분, results 60/10분, markets 4/분으로 시작합니다. limiter 장애는 fail closed입니다.
- start는 owner별 idempotency key를 사용하고, screening 도중 중단된 동일 키는 candidate/task upsert로 setup을 복구합니다.
- task 최대 시도 4회, retry_wait + jitter exponential backoff(최대 60초), 2분 lease fencing 및 run reconciliation을 추가했습니다. 부분 실패 run은 `completed_with_errors`로 구분합니다.
- 신규 migration: `supabase/migrations/20261114000200_auth_owner_recovery.sql`. 기존 `20261114000100_scanner.sql`은 그대로 보존했습니다.
- `npm.cmd run build`: 최종 exit 0. `npm.cmd run lint`: exit 0. Node 내장 테스트 5/5 통과.
- production 로컬 서버에서 session/markets/start는 인증 설정 누락으로 503을 반환해 fail-closed를 확인했습니다. 실제 로그인 성공과 거래소 호출은 실행하지 않았습니다.
- DB migration/E2E, owner mismatch의 DB 런타임, limiter 동시성, stale lease 경쟁, Vercel 설정과 배포는 미실행입니다. 실제 인증 환경변수 값은 만들거나 등록하지 않았습니다.
- 기존 코드 working tree 변경을 stage/commit하지 않았습니다. 문서 저장소에는 지시 범위의 보고서와 handover만 반영했습니다.

### 다음 단계

1. 전용 Supabase 프로젝트의 현재 schema/data/function owner/grant/policy/status를 read-only preflight로 점검합니다.
2. 별도 승인 후 migration을 적용하고 승인된 비밀 저장소에 인증 및 Supabase 환경변수를 구성합니다.
3. staging에서 1개 후보로 login, owner mismatch, idempotent start, 분산 limiter, retry/lease fencing, candle/result upsert를 검증합니다.
4. Vercel 보호 설정 및 배포는 별도 승인 후 진행합니다.
5. 원형파·후잔잔 상세 판정 규칙은 별도 확정 후에만 분석 로직에 반영합니다.


## 신규 migration 정적 검토 완료 (2026-11-14)

보고서: `reports/2026-11-14-migration-static-review.md`.

- `supabase/migrations/20261114000200_auth_owner_recovery.sql`과 기존 `20261114000100_scanner.sql`, TypeScript RPC 호출부를 읽기 전용으로 정적 검토했습니다.
- `supabase/preflight/20261114000200_auth_owner_recovery_preflight.sql`을 작성했습니다. catalog relation/column/function/ACL/RLS 조회와 guarded, aggregate-only row-state 조회로 구성했습니다.
- 자체 텍스트 audit: 금지된 변경 statement 시작 0, SELECT/WITH 시작 43, guarded query_to_xml 8, to_regclass guard 27, trailing whitespace 0. 이 검사는 SQL parser나 DB 실행 검증이 아닙니다.
- Migration / preflight SQL 모두 실행하지 않았습니다. Supabase 접속, DB query, 환경변수 접근/수정, migration 적용은 하지 않았습니다.
- BLOCKER: 실제 대상 schema/data/function owners/ACL/policies 상태가 미확인이고, preflight 자체도 원격에서 실행하지 않았습니다. 이 상태로 migration 적용을 권고하지 않습니다.
- 적용 전 추가로 확인할 stuck task 조건: attempts 한도 이상인 queued task, locked_at 없는 processing task, due time 없는 retry_wait task. Owner-null legacy run은 자동 backfill되지 않아 새 API에서 접근할 수 없습니다.
- 사용자 코드 working tree는 수정·stage·commit하지 않았습니다. 생성한 preflight 파일만 local project에 남아 있습니다. 문서 저장소에는 이 보고서와 handover만 반영했습니다.

### 다음 단계

1. Dashboard에서 올바른 dedicated Supabase project를 확인한 후, 승인된 read-only role로 preflight 결과를 수집합니다.
2. report의 blocker, schema drift, ACL/policy, function owner, duplicate key 및 task aggregate를 검토하고 legacy owner-null run 방침을 결정합니다.
3. 백업/restore 계획, atomic migration runner, active worker drain을 확인한 후 migration 적용을 별도 승인합니다.
4. 적용 후 staging에서 migration status, role grants, API authentication, idempotency, limiter concurrency와 retry/lease recovery를 검증합니다.
5. 환경변수, Vercel protection, 배포는 각각 별도 승인 후 진행합니다.


## Read-only preflight 보완 완료 (2026-11-14)

보고서: `reports/2026-11-14-migration-static-review.md` (보완 절 참조).

- preflight SQL에 task attempts 상태별 집계(queued/processing/retry_wait), 6개 대상 relation의 전체 constraints 및 CHECK, 전체 index/UNIQUE 정의, relation_kind 분류를 추가했습니다.
- candles/results의 full `count(*)`를 제거하고 `pg_stat_user_tables`의 estimated live/dead rows만 조회합니다.
- 텍스트 audit: 변경 statement 시작 0, SELECT/WITH 실행 문장 시작 42, query_to_xml 6, candles/results full count 0, trailing whitespace 0, EOF newline 있음. SQL 실행/parser 검증은 하지 않았습니다.
- migration, DB, 환경변수, package, 앱 코드는 변경하지 않았고 원격 Supabase 접속/쿼리도 하지 않았습니다.

다음 단계는 이전 섹션의 blocker 및 별도 승인 절차를 따릅니다. 원격 preflight 결과를 승인된 read-only role로 수집하기 전까지 migration 적용을 보류합니다.

## 로컬 개발 로그인 제한 보완 완료 (2026-11-14)

보고서: `reports/2026-11-14-local-login-rate-limit.md`.

- 로컬 로그인만 NODE_ENV=development, Vercel 미배포, configured Origin과 정확히 일치하는 loopback Origin일 때 프로세스 메모리 limiter를 사용합니다. 한도는 기존 로그인 정책과 동일한 5회/15분입니다.
- 운영/preview 조건 및 다른 Origin은 기존 Supabase RPC limiter 경로를 사용합니다. 분석 및 시장 API 제한과 Supabase 데이터 저장은 우회하지 않습니다.
- 비밀번호 비교, 서명 세션 검증, 만료, Origin 보호를 유지했습니다. 패키지, 환경변수, DB, migration은 변경하지 않았습니다.
- `npm.cmd run lint`: exit 0; 보안 테스트: 7/7; `npm.cmd run build`: exit 0.
- 실제 로그인 API 요청과 Supabase 검증은 수행하지 않았습니다. 로컬 카운터는 서버 프로세스 재시작 시 초기화됩니다.

로컬에서 기존 auth 설정을 사용하고 SCANNER_ALLOWED_ORIGIN을 개발 서버 Origin과 정확히 일치시켜 확인합니다. 운영 사용 전 Supabase 환경 및 migration은 별도 승인된 절차로 구성·검증해야 합니다.


## 로컬 분석 API 요청 제한 보완 완료 (2026-11-14)

보고서: `reports/2026-11-14-local-analysis-rate-limit.md`.

- 공통 `protectScannerApi()`를 사용하는 analysis start/step/status/results 네 scope를 조사하고, 로컬 메모리 limiter 분기를 추가했습니다. NODE_ENV=development, Vercel 미배포, configured loopback Origin과 정확한 일치 조건을 로그인과 공유합니다. GET에서 Origin이 없으면 Referer origin을 검사합니다.
- 제한 정책은 변경하지 않았습니다: start 3/10분, step 240/30분, status 320/30분, results 60/10분. markets와 그 외 scope는 기존 Supabase limiter를 사용합니다.
- 제한만 대체했습니다. run 생성, owner 검증, candidate/task/candle/result 저장과 status 조회는 기존 Supabase 경로를 유지합니다. Supabase 미설정이면 분석은 계속 fail-closed 합니다.
- `node --test tests/*.test.mjs`: 9/9; `npm.cmd run lint`: exit 0; `npm.cmd run build`: exit 0.
- DB/API end-to-end 검증, 원격 접속, 환경변수 및 migration 변경은 하지 않았습니다. 로컬 memory limiter는 개발 서버 재시작 시 초기화됩니다.


## 로컬 Origin 검증 보정 완료 (2026-11-14)

보고서: `reports/2026-11-14-local-origin-validation.md`.

- 로그인 POST와 analysis start/step POST는 동일한 `requireAllowedOrigin()` 검사를 사용합니다. status/results GET은 Origin guard 옵션 없이 세션을 확인하고, 개발 limiter 판정에 Origin이 없으면 Referer origin을 씁니다.
- 403은 limiter가 아니라 exact origin comparison에서 생성됩니다. URL normalization 후에도 localhost, 127.0.0.1, IPv6 loopback alias는 이전에 서로 다른 host로 비교될 수 있었습니다. 실제 Chrome 요청 header는 scanner tab이 열려 있지 않아 직접 수집하지 못했습니다.
- 개발 및 Vercel 미배포일 때만 loopback끼리 scheme/effective port가 같은 경우 alias를 인정하도록 보정했습니다. 다른 port/scheme, non-loopback은 거부하고 production은 HTTPS exact-origin 비교를 유지합니다.
- `node --test tests/*.test.mjs`: 9/9; `npm.cmd run lint`: exit 0; `npm.cmd run build`: exit 0.
- Supabase limiter와 데이터/작업/owner 검증은 변경하지 않았습니다. 실제 브라우저 및 DB end-to-end 검증은 미실행입니다.

로컬에서 browser host와 `SCANNER_ALLOWED_ORIGIN`이 same scheme/port loopback인지 확인한 후 다시 검증합니다. limiter 통과 뒤에도 Supabase 미설정 시 분석은 기존대로 fail-closed 해야 합니다.


### 로컬 Origin 런타임 확인 보충

추가 관찰: `reports/2026-11-14-local-origin-runtime-check.md`.

- 검토 시 `SCANNER_ALLOWED_ORIGIN`은 `http://localhost:3000`이었습니다. 이 값 외의 비밀 환경변수는 확인하지 않았습니다.
- 현재 점검 시점에는 3000/3001 listener가 없었고, 자동화에서 열린 Chrome 탭도 scanner가 아니어서 실패 요청의 실제 POST Origin/GET Referer를 관측하지 못했습니다.
- login/start POST는 같은 origin guard를 사용하므로 같은 origin/프로세스/설정이라면 결과가 같아야 합니다. 수정은 loopback host alias를 같은 scheme/port로 한정해 처리합니다. 실제 port mismatch가 있다면 계속 차단하며 configured origin을 실행 포트에 맞춰야 합니다.
- 따라서 코드-level comparison defect는 보정했지만, 사용자가 본 특정 요청의 runtime mismatch는 다음 로컬 실행 때 브라우저 Network에서 실제 Origin을 확인해야 최종 확정할 수 있습니다. 환경변수는 변경하지 않았습니다.


## Supabase 연결 사전 점검 완료 (2026-11-14)

보고서: `reports/2026-11-14-supabase-connection-preflight.md`.

- 신규 프로젝트용 migration은 00100 scanner schema → 00200 owner/rate-limit/retry extension 순서입니다. 6개 table, key/index/constraints, 6 RPC 및 RLS/grants를 정리했습니다. 모든 테이블은 RLS enabled이며 migration은 anon/authenticated policy를 생성하지 않고 backend service role로 접근합니다.
- dedicated Supabase project는 자체 Postgres/database를 가지므로 기존 family-learning/WORD MASTER 데이터와 분리하는 구성이 적합합니다. 이번에는 해당 프로젝트를 열거나 조회하지 않았습니다.
- 현재 연결 변수 이름은 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`; 앱 인증 설정은 `SCANNER_LOGIN_PASSWORD`, `SCANNER_SESSION_SECRET`, `SCANNER_ALLOWED_ORIGIN`입니다. 키 값은 읽거나 보고하지 않았습니다. `.env.local`은 `.gitignore`에 의해 무시되고 tracked file이 아닙니다. source search에서 NEXT_PUBLIC Supabase key 또는 browser DB call은 발견되지 않았습니다.
- 호환성 주의: 현재 helper는 legacy service_role key만 사용합니다. Supabase 공식 안내는 legacy 키를 2026년 말까지 폐기할 예정이라고 하므로 새 secret key 지원과 REST Authorization header 처리를 별도 코드 승인 작업으로 확인해야 합니다.
- Free plan은 $0, project당 500 MB DB, 낮은 7일 활동 시 자동 pause, 2 active free project organization/account quota 및 백업 부재를 고려해야 합니다. 정확한 요금/사용량 조건은 project 생성 직전에 공식 가격표와 Dashboard에서 다시 확인합니다.
- 코드/migration/환경변수 변경, project 생성/연결, remote DB, SQL 실행, build/test는 하지 않았습니다.

### 다음 연결 순서

1. legacy/new key compatibility와 코드 변경 승인 여부 결정
2. scanner 전용 project 및 비용/quota 승인
3. 신규 DB에서 migration 00100 적용
4. read-only 00200 preflight 실행 및 blocker 검토
5. 별도 승인 후 migration 00200 적용 및 backup/restore 계획 확인
6. server-only env 설정 승인 후 작은 후보 E2E, upsert, owner/limiter/recovery smoke test
7. storage/egress/backup/retention 점검 후 staging 및 배포는 별도 승인


## Supabase 신규 Secret Key 호환성 검토 (2026-11-14)

보고서: `reports/2026-11-14-supabase-secret-key-compatibility.md`.

- 현재 `lib/scanner/supabase.ts`는 `SUPABASE_SERVICE_ROLE_KEY`만 읽고 공통 REST/RPC 요청에 `apikey` 및 `Authorization: Bearer`를 함께 설정합니다. 따라서 legacy JWT service_role 경로만 고려돼 있으며 신규 `SUPABASE_SECRET_KEY`는 미지원입니다.
- Supabase 공식 안내에 따르면 신규 Secret Key는 Data API에서 `apikey` 헤더로만 보내야 합니다. 해당 키를 Bearer로도 보내면 JWT 파싱으로 `Invalid JWT`가 날 수 있습니다. Secret Key도 RLS를 우회하는 서버 전용 비밀값입니다.
- 제안 변경 범위는 helper 한 파일로 제한: URL + legacy/new 키 중 정확히 하나를 요구하고, 동시 설정은 fail closed, legacy는 두 헤더, 신규 secret은 apikey만 사용하며 입력된 Authorization도 제거합니다. CRUD/RPC와 no-store 및 오류 비노출은 보존합니다. 이번에는 코드 변경하지 않았습니다.
- 보안 테스트 계획: legacy/new 각 헤더 구성, 둘 다/둘 다 없음 fail-closed, CRUD/RPC 요청 보존, 오류·로그 비밀값 비노출, server-only 경계 확인. 구현 승인 전이므로 테스트/build/DB smoke test는 실행하지 않았습니다.
- 기존 migration 순서는 유지: `20261114000100_scanner.sql`을 먼저, 그 다음 첫 migration 적용 및 read-only preflight 검토 조건을 충족한 뒤 `20261114000200_auth_owner_recovery.sql`. 원격 DB 연결, SQL/migration 실행, 환경변수 및 package 변경, 프로젝트 생성은 하지 않았습니다.
- 신규 키 헤더에 대한 근거는 Supabase 공식 문서 [키 이전 가이드](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys), [API keys](https://supabase.com/docs/guides/getting-started/api-keys), [Data API routes](https://supabase.com/docs/guides/api/creating-routes)에 있습니다.

### 다음 단계

1. 별도 지시로 helper 키 모드 지원과 mock 기반 보안 테스트 구현을 승인합니다.
2. 구현 후 lint/build 및 테스트를 실행하고 기존 API 경로가 유지되는지 확인합니다.
3. 전용 Supabase 프로젝트 준비 및 별도 승인 전까지 원격 DB smoke test나 migration 적용은 하지 않습니다.


## Supabase 제거 및 로컬 SQLite 전환 — 사전 조사/승인 대기 (2026-11-14)

초기 조사 보고서: `reports/2026-11-14-sqlite-transition-initial-assessment.md`.

- 현재 local working tree에는 기존 사용자 코드 변경/미추적 파일이 있었고 그대로 보존했습니다. 로컬 `instructions/WORKFLOW.md`, `handover/STATUS.md`는 없어서 문서 저장소의 최신본을 읽었습니다. `.env.local`의 존재와 미추적 상태만 확인했으며 내용은 읽거나 기록하지 않았습니다.
- 현재 저장소는 `lib/scanner/supabase.ts`에 CRUD/RPC가 모여 있지만 analysis start/step/status/results, candle cache, auth/login limiter가 이를 호출합니다. 분석 엔진 및 거래소 수집 코드는 DB와 분리되어 있어 알고리즘은 유지하면서 저장 adapter를 교체할 수 있습니다.
- 코드 변경 전 기준: 보안 테스트 9/9, `npm.cmd run lint` exit 0, `npm.cmd run build` exit 0. Node v26.13.0에서 내장 `node:sqlite` 로딩은 확인했으나 Node 공식 문서상 Stability 1.2 Release Candidate입니다.
- Windows/Node 26 호환에 대해 공식 release notes가 Node 26 prebuilt를 기록한 mature `better-sqlite3`가 유력한 선택입니다. 다만 runtime dependency 추가 및 `package.json`/`package-lock.json` 변경이 필요하므로 지시서의 사전 승인 규칙에 따라 설치/구현은 대기합니다.
- 별도 승인 후 체크포인트 생성, SQLite adapter/schema, run/candidate/task/candle/result 저장 및 transaction/retry 복원, local rate limiter, Supabase env/code 제거, DB/backup gitignore 및 초기화/backup/restore 문서를 구현할 예정입니다. 실제 로컬 E2E와 재시작 persistence도 검증 예정입니다.
- Supabase 프로젝트/DB/migration은 접속·변경·삭제하지 않았고, 기존 migration 두 파일은 그대로 유지합니다. 소스 및 package는 이번 단계에서 변경하지 않았습니다.

### 다음 단계

사용자가 `better-sqlite3` runtime dependency 추가와 package manifest/lockfile 변경을 승인하면 체크포인트 후 구현을 시작합니다. 내장 `node:sqlite` 대안은 Release Candidate 안정성 등급이 있어 승인 후에도 선택이 필요하면 별도 지침을 확인합니다.


## Supabase runtime 제거 및 로컬 SQLite 전환 완료 (2026-11-14)

보고서: reports/2026-11-14-supabase-local-sqlite-transition.md. 이 절이 앞의 Supabase 연결 준비/키 호환성 단계보다 최신 상태입니다.

- Supabase REST/RPC helper 및 서버 호출을 제거했습니다. SQLite adapter는 data/scanner.sqlite에 runs, candidates, tasks, candles, results를 저장하며 WAL/foreign key/unique keys와 transaction을 적용합니다. DB/backup/WAL/SHM 및 소스 체크포인트는 Git ignore입니다.
- better-sqlite3@12.10.0을 Node 26.13.0 Windows x64에서 설치/로드 확인했습니다. DB 접근은 storage facade를 거쳐 이후 교체할 수 있습니다.
- 로그인, HMAC session, HttpOnly/SameSite 쿠키, 세션 만료, POST Origin 보호를 유지했습니다. auth Origin은 loopback만 허용하고 Vercel에서는 fail closed 합니다. dev/start 스크립트는 127.0.0.1로 바인딩합니다.
- login/start/step/status/results/markets 기존 요청 제한 정책을 유지하며 모두 local fixed-window memory limiter로 처리합니다. 카운터는 server restart 때 초기화됩니다.
- UI에 저장된 run history 불러오기 및 수동 이어가기 기능을 추가했습니다. DB 초기화와 PowerShell backup/restore 및 다른 Windows PC 이동 방법을 README에 기록했습니다.
- 최종 npm.cmd test: 12/12; npm.cmd run lint: exit 0; npx.cmd tsc --noEmit: exit 0; npm.cmd run build: exit 0.
- 실제 API: login 성공, 1개 후보 analysis start→step→status→results 완료. 전체 시장 2,107개(Binance 758/OKX 528/Bybit 821), 후보 1개, task 완료 1/실패 0. candle 저장 1h 501 / 4h 501 / 1d 415. 롱/숏 결과 각 1개는 qualified=false로 results qualified count는 0개.
- 재시작 후 로그인, history의 이전 run 1개, status/results 조회를 확인했습니다. 별도 /api/markets는 HTTP 200, 2,107개, 가격 누락 0, 오류 0, 705.2ms.
- server는 검증 후 종료했습니다. local data/scanner.sqlite의 테스트 run/candle/result 기록은 보존했습니다.
- .env.local, Supabase project, DB, migration, preflight SQL을 수정·적용하지 않았습니다. migration 두 개 및 preflight SQL은 지시대로 보존했습니다. app/lib runtime 검색에서 Supabase REST/RPC/env reference는 0건.
- npm 출력에 moderate audit advisories 6건이 있었지만 audit fix/upgrade는 하지 않았습니다. native install script 승인은 better-sqlite3@12.10.0 단일 버전으로 제한했습니다. 체크포인트 대비 lockfile 기존 package version 변경/삭제 0건입니다.

### 남은 제약 및 다음 단계

1. local limiter 메모리는 프로세스 재시작 때 초기화되고 프로세스 간 공유되지 않습니다. loopback 서버 하나만 실행합니다.
2. 실제 샘플은 long/short qualified 후보가 없습니다. 다른 후보 실행은 사용자가 수동으로 시작해야 합니다.
3. DB 복원 및 타 PC 이동 명령은 README에 적었지만 실제 수행하지 않았습니다.
4. 향후 인터넷 공개/다중 사용자 전환은 별도 프로젝트, 보안 설계 및 승인으로 진행합니다.
