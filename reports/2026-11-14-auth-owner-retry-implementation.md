# 04. 인증·소유권·작업 복구 구현 보고서

- 작업일: 2026-11-14
- 지시서: `instructions/04-auth-owner-retry-implementation.md`
- 코드 프로젝트: `C:\\Users\\PC1\\ai-trading-scanner`
- 범위: 앱 단일 사용자 인증, API 보호, 분산 호출 제한, idempotent start/recovery, task 재시도 및 신규 migration 작성
- 결과: 구현 및 로컬 검증 완료. 원격 DB 적용과 통합 검증은 미실행.

## 구현 내용

### 인증과 API 접근

- 서버 전용 `lib/scanner/auth.ts`와 비밀값 없는 핵심 로직 `lib/scanner/auth-core.ts`를 추가했습니다.
- 신규 환경변수 이름은 `SCANNER_LOGIN_PASSWORD`, `SCANNER_SESSION_SECRET`, `SCANNER_ALLOWED_ORIGIN`으로 한정했습니다. 모두 없거나 형식이 잘못되면 fail closed로 처리하고 응답에는 누락된 변수 이름만 포함합니다.
- HMAC-SHA256 서명 세션(8시간)을 사용합니다. 서명 비교와 비밀번호 비교는 timing-safe 비교를 사용합니다. 쿠키는 HttpOnly, SameSite=Strict, Path=/이며 production Secure를 적용합니다.
- Origin은 설정된 canonical origin과 정확히 비교하며 production의 비 HTTPS origin을 거부합니다. 로그인·로그아웃은 Origin 검사를 거칩니다.
- 로그인 제한은 신뢰 가능한 Vercel 전달 IP 기반의 DB limiter를 사용합니다. 인증 후 `/api/analysis/start|step|status|results`와 `/api/markets`를 보호합니다. 민감한 API 응답은 `Cache-Control: no-store`를 지정하고, 세션 만료 401은 화면 polling을 중단하고 로그인 상태로 돌립니다.
- run은 서버의 고정 principal ID로 생성합니다. status/results 조회와 task claim RPC에 owner 조건을 전달하고, 소유자가 없거나 다른 run은 404로 감춥니다.

### 호출 제한 및 중복 실행 복구

DB RPC에 사용하는 제한은 코드 상수이며 클라이언트가 조정할 수 없습니다.

| 경로 | 제한 |
| --- | ---: |
| 로그인 | 5회 / 15분 / 신뢰 IP |
| 분석 시작 | 3회 / 10분 / principal |
| 분석 step | 240회 / 30분 / principal 및 run |
| 분석 status | 320회 / 30분 / principal |
| 분석 results | 60회 / 10분 / principal |
| markets | 4회 / 1분 / principal |

- limiter는 원자 DB RPC와 HMAC 해시 subject를 사용합니다. RPC 오류는 fail closed, 제한 초과는 429와 Retry-After를 반환합니다. 인스턴스 메모리 Map은 사용하지 않습니다.
- owner와 idempotency key unique index 및 `begin_scanner_run` RPC로 동일 키의 중복 run 생성을 막습니다. 화면은 동일 키로 시작 요청을 제한 재시도합니다.
- run이 `screening` 도중 중단된 동일 키 요청은 저장된 설정으로 시장 선별을 다시 수행하고 candidate/task upsert로 setup을 복구합니다. setup 완료 후에는 `queued`로 전환됩니다.

### task 복구 및 상태 정산

- 각 task 최대 시도는 4회입니다. 요청 묶음 크기는 기존 설정의 1–3개 범위를 사용합니다.
- 내부 개별 fetch 재시도 루프는 제거하고, task 단위 jitter exponential backoff(최대 60초)가 retry를 소유하도록 했습니다. 최대 4번의 task claim으로 재시도가 유한합니다.
- 429, 5xx, CCXT timeout/rate-limit/network 오류는 `retry_wait`로 돌리고, 잘못된 입력 등 영구 오류는 terminal `failed`로 정산합니다. DB HTTP 오류도 status가 429/5xx이면 transient 정책에 들어갑니다.
- claim은 2분 lease와 새 lease token을 발급합니다. candle/result 저장 및 완료·실패 RPC는 현재 token을 확인하므로 stale worker는 결과를 덮어쓰지 못합니다.
- run reconciliation은 DB에서 task 상태를 원자 집계해 `queued`, `processing`, `completed`, `completed_with_errors`, `failed`를 구분합니다. task가 없는 정상 run은 `completed`입니다.

### Migration 및 보안 결정

- 신규 파일: `supabase/migrations/20261114000200_auth_owner_recovery.sql`
- 기존 `20261114000100_scanner.sql`은 수정하지 않았습니다.
- 신규 migration은 nullable `owner_id`, idempotency unique index, status 제약, attempt/retry/lease 필드, limiter table/RPC, owner-aware claim, fenced complete/failure, reconciliation RPC를 추가합니다.
- SECURITY DEFINER 함수는 `search_path = pg_catalog`을 고정하고 테이블을 schema-qualified로 참조합니다. 실행 권한은 service_role에만 부여하며 기존 owner-less claim RPC 권한을 취소합니다.
- 기존 run의 owner를 임의 backfill하지 않습니다. 기존 행과 constraint/function/grant/policy가 예상과 다르면 read-only preflight 후 별도 계획이 필요합니다.
- 실제 migration SQL 적용, schema validation, 함수 grant 및 동시성 검증은 하지 않았습니다. migration 상단의 preflight/적용 조건을 먼저 따르십시오.

## 변경 파일

신규/추가:

- `app/api/auth/login/route.ts`, `logout/route.ts`, `session/route.ts`
- `lib/scanner/auth-core.ts`, `auth.ts`, `rate-limit.ts`, `recovery-policy.ts`
- `supabase/migrations/20261114000200_auth_owner_recovery.sql`
- `tests/scanner-security.test.mjs`

수정:

- `app/api/analysis/start/route.ts`, `step/route.ts`, `status/route.ts`, `results/route.ts`
- `app/api/markets/route.ts`
- `lib/scanner/supabase.ts`, `types.ts`
- `app/page.tsx`, `app/layout.tsx`, `app/globals.css`
- `next.config.ts`

`app/page.tsx`와 `app/layout.tsx`, `package.json`, `package-lock.json`, API/lib/migration 디렉터리에는 작업 전부터 사용자 변경이 있었습니다. 이 변경을 초기화하거나 package 파일을 수정하지 않았고, 코드 프로젝트에서는 파일을 stage/commit하지 않았습니다.

## 검증 결과

- `npm.cmd run build`: **exit 0**. Next.js production compile, TypeScript, static generation 완료.
  - 첫 실행은 Next.js가 상위 `C:\\Users\\PC1\\package-lock.json`을 workspace root로 선택해 권한 오류가 났습니다. 프로젝트 `next.config.ts`에서 Turbopack root를 현재 작업 폴더로 고정했습니다.
  - 이후 빌드는 Google Fonts 다운로드 실패로 멈췄습니다. layout metadata와 화면 구성은 유지하면서 외부 폰트 fetch를 제거하고 system font fallback을 설정한 뒤 성공했습니다.
- `npm.cmd run lint`: **exit 0**.
- `node --experimental-strip-types --disable-warning=MODULE_TYPELESS_PACKAGE_JSON --test tests/scanner-security.test.mjs`: **5/5 통과**. 세션 서명/만료/변조, 비밀번호 비교, Origin 검사, cookie 정책, run 상태 및 retry 정책을 검증했습니다.
- Production 서버 수동 요청: `/api/auth/session`, `/api/markets`, `POST /api/analysis/start` 모두 **HTTP 503**과 필요한 인증 환경변수 이름을 반환했습니다. 설정 누락 시 닫히는 동작을 확인했으며 인증이 없어 거래소 조회는 시작되지 않았습니다.
- Supabase/SCANNER 환경변수 값은 읽거나 변경하지 않았고 새 값을 만들거나 등록하지 않았습니다.

## 실행하지 않은 검증 및 남은 위험

- Supabase migration 적용, DB integration/E2E, 실제 로그인 성공, owner mismatch의 DB 런타임 차단, 동시 idempotency, multi-instance rate limit, stale lease 경쟁 검증은 미실행입니다.
- Vercel 환경, maxDuration, Deployment Protection/WAF, 비밀값 설정, 배포는 변경하거나 검증하지 않았습니다.
- HMAC stateless session은 로그아웃으로 기존 토큰 전체를 폐기할 수 없습니다. 전체 폐기는 session secret 회전이 필요합니다.
- Limiter 한도와 lease/attempt 정책은 코드 및 SQL의 초기 값입니다. staging 관찰 후 사용자 승인 아래 조정해야 합니다.
- Existing run의 nullable owner 데이터는 자동으로 소유 처리되지 않으므로 기존 run은 새 API에서 조회되지 않습니다.

## 다음 단계

1. 전용 Supabase 프로젝트에서 migration preflight를 읽기 전용으로 수행하고 기존 데이터/함수/권한을 확인합니다.
2. 별도 승인 후 migration을 적용하고 승인된 비밀 저장소에 세 인증 환경변수 및 Supabase 연결 설정을 구성합니다.
3. staging에서 1개 후보로 login, owner mismatch, 중복 start, rate limit 동시성, task 재시도/lease fencing 및 결과 저장을 검증합니다.
4. Vercel 보호 설정과 배포는 별도 승인 후 진행합니다.
