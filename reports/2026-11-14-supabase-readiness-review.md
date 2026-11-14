# Supabase 준비 상태 및 migration 안전성 검토

- 검토일: 2026-11-14
- 대상 코드 프로젝트: `C:\Users\PC1\ai-trading-scanner`
- 코드 브랜치: `master`
- 문서 브랜치: `main`
- 범위: 정적 코드·SQL 검토와 로컬 빌드만 수행. 원격 DB, 환경변수, 코드, 배포는 변경하지 않음.

## 요약

현재 전용 Supabase에 적용하거나 실제 연결할 준비가 끝났다고 판정할 수 없습니다. migration에는 테이블·키·인덱스, RLS 활성화, 제한된 task claim RPC가 정의되어 있고, 코드에는 candle/result upsert가 있습니다. 그러나 로컬 접속 설정이 없으므로 실제 role, 기존 schema/policies, DB 연결 및 end-to-end 쓰기는 확인하지 못했습니다.

**공개 배포 전에 High 두 항목을 해소해야 합니다:** 분석 API에 인증·접근 제한이 없고, migration은 기존 객체의 호환성을 검사하지 않습니다. 전용 빈 프로젝트인지 확인하기 전에는 migration을 적용하지 마십시오.

## 검토한 파일

### 코드 프로젝트

- `supabase/migrations/20261114000100_scanner.sql` 전체
- `lib/scanner/supabase.ts`
- `lib/scanner/candles.ts`
- `lib/scanner/types.ts`
- `app/api/analysis/start/route.ts`
- `app/api/analysis/step/route.ts`
- `app/api/analysis/status/route.ts`
- `app/api/analysis/results/route.ts`
- `app/page.tsx`
- `package.json`
- Git branch/status 및 환경변수 설정 여부(값은 읽거나 출력하지 않음)

### 문서 저장소

- `instructions/02-supabase-readiness-review.md`
- `instructions/WORKFLOW.md`
- `reports/README.md`
- 기존 `handover/STATUS.md`

## 구조 및 데이터 흐름

- `scanner_runs`: 실행 설정, 거래소 상태 및 진행 카운터
- `scanner_candidates`: run별 거래소·심볼 후보와 선정 사유
- `scanner_tasks`: 후보 작업 queue, attempts, lease timestamp 및 오류
- `scanner_candles`: OHLCV. PK `(exchange,symbol,timeframe,timestamp_ms)`
- `scanner_results`: 방향별 결과. unique `(run_id,candidate_id,side,algorithm_version)`
- FK는 run/candidate 삭제 때 하위 rows가 cascade 삭제되도록 정의됨. migration 자체에는 `DROP`, `TRUNCATE`, `DELETE`가 없음.
- 브라우저의 사용자 시작 요청 → `/api/analysis/start`가 run·후보·task 생성 → `/api/analysis/step`이 task claim 및 OHLCV/결과 저장 → status/results API가 상태·결과를 읽음.
- `lib/scanner/supabase.ts`는 서버 프로세스의 `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`를 사용해 PostgREST 요청을 보냄. 해당 모듈은 현재 서버 route에서 사용되고, `app/page.tsx`에서는 scanner type만 `import type`으로 사용됨.
- candle 저장은 exchange/symbol/timeframe/timestamp 충돌 시 `resolution=merge-duplicates`; 결과 저장도 run/candidate/side/algorithm version 충돌 키로 upsert.

## 항목별 판정

### 정상으로 확인된 구현

- **Task claim 원자성:** RPC는 단일 CTE에서 `FOR UPDATE SKIP LOCKED`로 due task를 선택하고 UPDATE하여 claim합니다. 중복 worker가 같은 시점의 동일 row를 동시에 가져가는 것을 방지하는 구조입니다.
- **RPC 권한:** `SECURITY DEFINER` 함수에 대해 `PUBLIC`, `anon`, `authenticated` 권한을 revoke하고 `service_role`에만 execute를 grant합니다.
- **RLS 기본 설정:** 5개 테이블 모두 RLS를 enable합니다. 새 DB에서 migration이 만든 정책은 없으므로 anon/authenticated는 정책에 따른 접근이 허용되지 않습니다. 서버 service role 사용만을 전제로 한 형태입니다.
- **중복 저장:** 캔들 PK와 결과 unique key가 재실행 중 중복 row를 방지하고, PostgREST upsert 옵션이 이에 맞는 conflict key를 전달합니다.
- **실행 분할:** step route의 `maxDuration=60`, 설정 batch 상한 3, 거래소별 처리 및 캔들 fetch 3회 재시도(backoff)가 있습니다. candidate 상한 300과 task 상태 조회 limit 1000은 서로 범위가 맞습니다.
- **환경변수 사용 경로:** service role 값은 `NEXT_PUBLIC_*`가 아닌 서버 측 `process.env`에서 읽습니다. 이 검토에서 실제 값은 출력하지 않았습니다.

### 문제 및 위험

#### High — 분석 API에 인증·호출 제한이 없음

`start`, `step`, `status`, `results` route에 사용자 인증/소유권 검사가 없습니다. Supabase 변수 설정 후 공개 배포하면 누구나 start를 호출해 exchange·DB 사용량을 만들 수 있습니다. runId를 아는 사용자는 다른 실행의 상태·결과를 조회하거나 step을 호출할 수도 있습니다. service role은 RLS를 우회하므로 RLS만으로 이 API를 보호하지 못합니다.

**조치:** 공개 배포 전에 인증, run 소유권 검사, 시작/step rate limit을 추가하고 service role을 사용하는 API를 보호해야 합니다. 이는 코드/외부 설정 변경이므로 별도 승인 범위에서 진행합니다.

#### High — migration은 전용 빈 DB에 대한 사전 검증을 하지 않음

`CREATE TABLE/INDEX IF NOT EXISTS`는 같은 이름의 기존 객체가 올바른 구조인지 검증하거나 누락 column/constraint를 보완하지 않습니다. 반면 기존 이름의 테이블에도 RLS enable 및 grant를 수행하고, `claim_scanner_tasks(uuid,integer)` 함수는 `CREATE OR REPLACE`로 덮어씁니다. 기존 정책이나 권한도 migration에서 검사·제거하지 않습니다. 따라서 기존 데이터가 즉시 삭제되는 SQL은 없지만, 동명 객체·함수·정책이 있는 DB에서는 호환성 및 접근 제어가 예상과 달라질 수 있습니다.

**조치:** 전용 Supabase 프로젝트가 별도의 빈 대상인지 확인하고, 적용 전 catalog에서 동명 테이블·함수·policy·grant·extension을 확인해야 합니다. 다른 업무 DB에는 적용하지 마십시오.

#### High — task lease 만료 후 무제한 재claim 가능

RPC는 2분이 지난 `processing` task를 다시 claim하고 `attempts`를 증가시키지만 최대 attempts 조건이 없습니다. 정상적으로는 step의 60초 상한보다 lease가 길어 여유가 있으나, DB 지연·호스트 차이·반복 crash 시 같은 작업이 계속 재claim될 수 있습니다. CCXT 호출 실패는 3회 뒤 task를 `failed`로 마감하지만, lease로 회수된 worker crash는 별도 dead-letter/attempt 제한이 없습니다.

**조치:** 배포 환경의 최대 실행시간을 확인하고 lease 여유를 검증하십시오. 최대 attempts, stale task 종료/수동 재시도 절차, run 상태 복구를 정한 뒤 DB 변경이 필요하면 별도 승인 후 migration으로 반영해야 합니다.

### Medium — SECURITY DEFINER 함수의 search_path가 `public` 단독

함수는 `SECURITY DEFINER`이고 `SET search_path = public`입니다. 테이블 참조는 `public.`으로 schema-qualified되어 있지만 기본 함수·연산자 이름 탐색은 public 경로의 객체에 영향을 받을 수 있습니다. DB의 실제 public schema CREATE 권한과 함수 owner는 연결이 없어 확인하지 못했습니다.

**조치:** 전용 DB에서 public schema의 CREATE 권한 및 함수 owner를 확인하십시오. 적용 전 함수 본문을 schema-qualified하게 유지하고 안전한 고정 search_path/권한 구성을 DBA 검토로 확정하십시오.

### Medium — 기존 role grants와 policies를 명시적으로 정리하지 않음

RLS enable 및 service_role grant는 있지만 anon/authenticated에 대한 table grant revoke나 기존 policy 검사/삭제는 없습니다. 새 DB의 no-policy 상태는 RLS가 접근을 차단하지만, 기존 DB에 과거 정책이 있다면 이 migration은 이를 제거하지 않습니다. service_role에는 코드에서 쓰지 않는 DELETE 권한도 부여합니다.

**조치:** 새 DB의 effective grants/policies를 확인하십시오. 기존 객체를 재사용하지 말고, 최소 권한 원칙에 따라 필요한 권한만 검토하십시오. 정책 추가·변경은 사용자 승인 후 수행해야 합니다.

### Medium — 다중 단계 run 생성은 하나의 원자적 트랜잭션이 아님

start route는 run insert 후 거래소 수집, 후보의 여러 batch insert, task batch insert, run 상태 update를 순차 수행합니다. 중간 오류가 나면 run은 failed로 바뀌지만 앞서 생성한 후보 또는 일부 task는 남을 수 있습니다. 코드에는 DB transaction/RPC로 묶는 경로가 없습니다.

**조치:** 소수 후보의 실패 주입 테스트를 계획하고, partial run을 복구/정리할 운영 절차를 정하십시오. 트랜잭션 RPC가 필요하면 별도 승인 후 설계합니다.

### Low — service-only 보호가 소스 구조상 명시되지 않음

현재 확인한 import graph에는 client 번들이 service key를 직접 참조하는 import가 없습니다. 다만 Supabase helper가 `server-only` guard를 두지 않으므로 향후 실수로 client module에서 import하는 것을 빌드 단계에서 차단하지 않습니다.

**조치:** 코드 변경이 승인되는 단계에서 server-only 경계를 명시적으로 적용하고 client bundle 검증을 추가하십시오.

## 실환경 검증 불가

- `SUPABASE_URL` 설정 여부: 미설정
- `SUPABASE_SERVICE_ROLE_KEY` 설정 여부: 미설정
- `.env.local`: 없음
- 비밀값은 출력하거나 수정하지 않음
- 원격 DB 접속, 실제 role/RLS/policy/extension 확인, migration dry-run/apply, DB 저장·upsert, lease 동시성은 실행하지 않음
- Vercel 프로젝트 인증·플랜·실제 function timeout 설정은 확인하지 않음
- 따라서 현재 migration의 SQL 성공, service_role의 실효 권한, 실제 DB의 데이터 보존 여부는 **검증되지 않음**

## migration 전 필수 확인 및 안전한 적용 순서

1. 사용자가 전용 Supabase 프로젝트와 적용 대상을 승인한다. 가족 학습관리 프로젝트나 다른 DB를 재사용하지 않는다.
2. 프로젝트 ref/소유자가 대상과 일치하는지 관리자가 확인한다. DB URL·service key는 보고서/터미널/Git에 출력하지 않는다.
3. migration 파일의 SHA와 전체 내용을 review하고, DB catalog에서 동명 table/column/constraint/index/function, RLS policy, grants, pgcrypto 상태를 read-only 확인한다.
4. DB가 신규 전용인지 확인한다. 기존 객체가 있거나 출처가 불명확하면 중단하고 호환성 계획을 먼저 승인받는다.
5. 승인 후 새 전용 DB에 백업/복구 가능성을 확인하고 migration을 적용한다. 이 검토에서는 적용하지 않는다.
6. DB에서 table/PK/unique/FK/index, RLS와 role grants, 함수 owner·definition·execute grants를 다시 읽어 확인한다.
7. 인증이 있는 소수 후보(예: 1개)로 start → step → status → results를 실행한다. 캔들 upsert를 같은 입력으로 두 번 확인하고 중복 row가 생기지 않는지 확인한다.
8. 동시 step 요청, exchange 오류, DB 오류, lease 만료/crash를 staging에서 확인한다. 실패/재claim 후 진행률과 task 상태를 대조한다.
9. API 접근 제어 및 Vercel function 제한이 확인되기 전에는 public 배포하지 않는다.

## 명령 및 실제 결과

- 사전 상태 확인: `git branch --show-current` → `master`
- 사전·사후 `git status --short --branch`: 기존 변경은 `app/layout.tsx`, `app/page.tsx`, `package.json`, `package-lock.json`, 미추적 `app/api/`, `lib/`, `supabase/`이며 이 검토에서 코드 파일은 바꾸지 않음
- `npm.cmd run build` 첫 실행: Turbopack이 상위 `C:\Users\PC1` 디렉터리를 읽으려다 sandbox `Access denied (os error 5)`로 실패
- 같은 빌드를 승인된 escalation으로 재실행: **종료 코드 0**, 컴파일·type check·정적 페이지 생성·trace 완료
- 별도 단위/통합 테스트는 실행하지 않음. DB 환경 부재로 DB 테스트도 실행 불가

## 변경 여부

- 코드/SQL, 환경변수, 원격 DB, 배포 변경: 없음
- 코드 프로젝트 Git status는 검토 전과 동일한 기존 변경 상태임
- 문서 저장소에서는 이 보고서와 `handover/STATUS.md`만 변경

## 다음 조치 및 승인 필요 항목

1. 인증·소유권·rate-limit 개선을 위한 코드 작업 승인 및 구현
2. 전용 Supabase 프로젝트 선정과 migration 대상/적용 승인
3. migration 보안·기존 객체 preflight 검토 및 필요한 변경 승인
4. 환경변수 등록 승인 후 비밀 저장소에 URL/service role key 설정
5. staging DB에서 소수 후보 end-to-end/중복 upsert/실패 복구 테스트
6. Vercel 접근 제한 및 maxDuration/lease 검증 후 배포 승인
