# SQLite 로컬 전환 사전 조사 및 기준 상태 (2026-11-14)

## 목적과 범위

Supabase 완전 제거 및 로컬 SQLite 전환 지시를 받아, 현재 코드 결합 지점과 테스트 기준을 확인하고 안전한 구현 경로를 검토했습니다. 사용자는 Windows 단일 PC 로컬 실행, 기존 화면·분석 알고리즘 유지, 영속 run/candidate/task/candle/result 저장을 요구합니다.

아직 소스, package, 설정, SQL, 환경변수는 수정하지 않았습니다. 원격 Supabase 연결/변경, migration 실행, 외부 배포도 하지 않았습니다. 패키지 변경은 지시서에서 별도 승인 대상으로 지정되어 있어 대기 중입니다.

## 작업 규칙 및 현재 변경 상태

- 문서 저장소의 `instructions/WORKFLOW.md`와 `handover/STATUS.md`를 확인했습니다. 코드 저장소와 문서 저장소의 경계를 유지하고, 기존 변경을 보존하며, 코드 변경 후 report와 handover를 갱신하도록 규정합니다.
- 코드 프로젝트 브랜치: `master`.
- 작업 시작 전 working tree에는 이미 `app/globals.css`, `app/layout.tsx`, `app/page.tsx`, `next.config.ts`, `package.json`, `package-lock.json` 변경과 `app/api/`, `lib/`, `supabase/`, `tests/` 미추적 내용이 있었습니다. 이를 덮어쓰거나 stage하지 않았습니다.
- 로컬 `instructions/WORKFLOW.md`, `handover/STATUS.md`는 코드 프로젝트 안에 없으므로 문서 저장소 최신본을 확인했습니다.
- `.env.local`은 존재하지만 내용을 열거나 출력하지 않았습니다. Git 추적 상태를 확인했고 추적되지 않습니다. 기존 값은 변경하지 않았습니다.

## 현재 코드에서 확인한 Supabase 결합

### 인증 및 세션

`lib/scanner/auth.ts`와 `auth-core.ts`는 로그인 비밀번호 비교, HMAC 서명 세션, HttpOnly/SameSite 쿠키, 만료, Origin 검증을 처리합니다. `app/api/auth/login/route.ts`는 Supabase limiter와 결합된 예외 처리를 가지고 있습니다. 로그인 자체의 세션 발급은 DB를 직접 사용하지 않으므로 저장소 전환 후 유지할 수 있습니다. 개인 PC 단일 사용 구조에 맞춰 Origin/loopback와 신뢰 가능한 클라이언트 IP 처리의 전제를 재점검해야 합니다.

### 저장 helper와 요청 제한

`lib/scanner/supabase.ts`는 `server-only` REST helper이며 다음을 구현합니다.

- `scanner_runs`, `scanner_candidates`, `scanner_tasks`, `scanner_candles`, `scanner_results` 접근
- `begin_scanner_run`, `consume_scanner_rate_limit`, `claim_scanner_tasks`, `complete_scanner_task`, `finish_scanner_task_failure`, `reconcile_scanner_run` RPC
- batch insert, upsert, patch, select

`lib/scanner/rate-limit.ts`는 로컬 메모리 limiter를 auth login과 analysis scopes의 개발 조건에서만 사용하고, 일반 경로에서는 Supabase RPC로 요청 제한을 저장합니다. 로컬 단일 사용자 전환에서는 limiter를 프로세스 메모리 기반으로 통일하고, 기존 scope별 횟수/시간 정책은 보존할 수 있습니다. 재시작 시 메모리 한도가 초기화되는 것은 로컬 한계입니다.

### Route별 데이터 결합

- `/api/analysis/start`: Supabase 설정 확인, run 생성/idempotency, candidates/tasks 저장, run 상태 갱신
- `/api/analysis/step`: run/candidate 읽기, task claim, 거래소 캔들 수집/기존 candle 재사용, 분석 결과 및 candle 원자 저장, 실패/retry, run reconciliation
- `/api/analysis/status`: owner가 일치하는 run 조회
- `/api/analysis/results`: owner가 일치하는 run 확인 후 result/candidate 조회
- `/api/auth/login`: Supabase 설정 예외를 처리하는 limiter
- `lib/scanner/candles.ts`: Supabase helper를 통해 종료 candle 읽기 및 upsert
- `/api/markets`: Supabase 데이터 직접 접근은 없고 인증/limiter helper에 간접 의존

`lib/scanner/analysis-engine.ts`, `candidate-screen.ts`, `exchanges.ts`, `config.ts`, `recovery-policy.ts`는 DB에 직접 의존하지 않으며 유지 가능한 분석/거래소 층입니다.

### 환경변수

직접 확인한 코드 참조 이름:

- Supabase: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- 앱 인증: `SCANNER_LOGIN_PASSWORD`, `SCANNER_SESSION_SECRET`, `SCANNER_ALLOWED_ORIGIN`
- 실행 환경 판별: `NODE_ENV`, `VERCEL`

비밀값은 확인하거나 기록하지 않았습니다. Supabase 변수 참조는 helper와 이를 사용하는 route/limiter에 집중돼 있어 제거 대상이 구체적입니다.

### 기존 저장 구조

현재 Supabase migration에는 `scanner_runs`, `scanner_candidates`, `scanner_tasks`, `scanner_candles`, `scanner_results` 테이블과 run/task/rate-limit RPC가 정의돼 있습니다. 코드의 재시도/lease/idempotency와 candle 복합 키·upsert 동작을 SQLite transaction 및 유니크 제약으로 보존해야 합니다. 기존 DB migration 두 파일은 Supabase에 적용하지 않으며 수정/삭제하지 않는 것이 지시 범위에 부합합니다.

## Node/SQLite 조사 및 승인 경계

현재 개발 런타임은 Node.js v26.13.0이며 `node:sqlite` 모듈이 로드되고 Database/DatabaseSync API가 노출되는 것을 확인했습니다. Node 공식 문서는 이 모듈을 **Stability 1.2 — Release Candidate**로 표시합니다. 사용자의 요청은 안정적인 방식을 우선 검토하도록 하므로, 이를 장기 로컬 DB의 기본 선택으로 즉시 확정하지 않았습니다.

성숙한 대안인 `better-sqlite3`는 동기 API, transaction, WAL 지원을 제공하며 공식 저장소의 v12.10.0 release notes는 Node.js v26 prebuilt 추가를 기록합니다. 이 선택은 runtime dependency 추가와 `package.json`/`package-lock.json` 변경, Windows native binary 설치 검증을 요구합니다. 작업 지시가 패키지 설치/제거/버전 변경은 먼저 사유와 영향을 보고하고 승인 대기하라고 하므로 **현재 구현은 이 승인 지점에서 멈췄습니다**.

공식 근거:

- [Node.js SQLite API](https://nodejs.org/api/sqlite.html) — 현재 Node 26 내장 모듈은 Release Candidate (Stability 1.2)로 표시됩니다.
- [better-sqlite3 README](https://github.com/WiseLibs/better-sqlite3/blob/master/README.md) — 설치, transaction, sync API, WAL 및 Node 지원 요구를 설명합니다.
- [better-sqlite3 releases](https://github.com/WiseLibs/better-sqlite3/releases) — v12.10.0에서 Node.js v26 사전 빌드 지원을 명시합니다.

## 기준 테스트 상태

코드 변경 전 실행:

- `node --test tests/*.test.mjs`: 종료 코드 0, 9/9 통과
- `npm.cmd run lint`: 종료 코드 0
- `npm.cmd run build`: 종료 코드 0, Next.js 15.5.29 production build 성공
- Node SQLite 기능 확인: `node:sqlite` import 성공. 위에서 설명한 API 안정성 등급 때문에 이 사실만으로 구현 선택을 완료하지 않았습니다.

이번 단계에서 개발 서버나 실거래소 데이터 수집/분석은 실행하지 않았습니다.

## 승인 후 제안 구현 순서

1. `better-sqlite3` runtime dependency 추가 승인 및 Windows Node 26 native installation 확인
2. 소스 변경 전 기존 working tree 변경을 보존하는 프로젝트 내부 체크포인트 생성 (비밀값, `.env.local`, `node_modules`, `.next`, SQLite 파일 제외)
3. `lib/scanner/db/` 같은 adapter 계층, schema version/migration, 안전한 `data/` 경로, WAL 및 외래키 설정 구현
4. runs/candidates/tasks/candles/results, limiter persistence policy 중 필요한 local behavior 및 transaction, claim/retry/reconcile을 local DB에 구현
5. API route의 Supabase 접근을 adapter로 옮기고 분석 algorithm과 market collection을 보존
6. 로컬 limiter, 로그인/Origin/세션 설정 정리; 운영/cloud mode는 이번 범위에서 제거
7. DB 초기화/백업/복구를 명시적 안전 명령이나 문서로 제공하고, 기존 DB 파일은 자동 삭제하지 않음
8. `.gitignore`에 DB/WAL/SHM/backup 파일 경로를 추가
9. 보안·store/API route 테스트, lint, build, dev server, 실제 로컬 login/start/step/status/results, restart persistence 검증
10. Supabase 이름 및 API 호출이 남았는지 검색. 기존 SQL migration은 실행/변경하지 않음.
11. 상세 report와 handover를 문서 저장소 main에 업데이트

## 현재 미해결 및 다음 조치

- 구현은 패키지 승인 대기 중이므로 시작하지 않았습니다. 요청 승인 대상은 `better-sqlite3`를 로컬 runtime dependency로 추가하여 `package.json`과 `package-lock.json`을 갱신하고 Windows/Node 26 설치 검증을 하는 작업입니다.
- 승인이 나면 먼저 체크포인트를 만들고 구현을 진행할 수 있습니다. 승인되지 않으면 내장 `node:sqlite`를 쓰는 대체안은 Release Candidate 상태와 TypeScript typing/Node 버전 요구를 수용할지 별도 결정이 필요합니다.
- 아직 로컬 SQLite schema/data는 없습니다. 기존 Supabase 데이터를 이전할 원격 접속이나 DB 변경은 금지 상태로 유지합니다.
- 외부 공개/배포, 다른 프로젝트 접근, Supabase 프로젝트 삭제/변경은 이번 작업 범위 밖입니다.
