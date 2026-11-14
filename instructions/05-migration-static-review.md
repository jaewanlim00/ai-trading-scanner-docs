# 05. 신규 migration 정적 보안 검토 및 DB read-only preflight 준비

- 기준일: 2026-11-14
- 대상 코드 프로젝트: `C:\Users\PC1\ai-trading-scanner`
- 신규 migration: `supabase/migrations/20261114000200_auth_owner_recovery.sql`
- 이전 구현 보고서: `reports/2026-11-14-auth-owner-retry-implementation.md`
- 목적: migration을 실제 DB에 적용하기 전에 SQL 자체의 안전성과 적용 전 확인 절차를 독립적으로 점검한다.

## 엄격한 작업 제한

이번 단계는 **정적 코드/SQL 검토와 read-only preflight 자료 준비만** 허용한다.

절대 하지 말 것:
- Supabase에 연결하거나 원격 DB에 쿼리 실행
- migration 실행 또는 SQL Editor에 붙여넣기
- DB schema/data/function/policy/grant 변경
- 환경변수 또는 비밀값 읽기·생성·등록
- Vercel 설정, 배포, 패키지 변경
- 코드 구현 변경(문서에서 수정 필요점을 제안하는 것은 허용)
- 기존 working tree 변경을 stage/commit하거나 되돌리기

## 작업

1. 최신 `instructions/WORKFLOW.md`, `handover/STATUS.md`, 구현 보고서를 읽는다.
2. 코드 프로젝트의 현재 working tree를 확인하되 어떤 파일도 수정하지 않는다. migration 파일과 기존 `20261114000100_scanner.sql`을 함께 읽고 차이를 검토한다.
3. 신규 migration 전체를 정적으로 검토한다. 특히 아래 항목을 구체적으로 확인한다.
   - 기존 테이블/컬럼/enum/status와의 호환성, 기존 데이터가 있을 때의 동작
   - nullable owner와 owner-less 기존 run/task의 처리 및 API 접근 영향
   - unique index와 idempotency key의 null/중복 의미
   - RPC 인자·반환형·호출부 TypeScript 인자 일치
   - SECURITY DEFINER, 함수 owner, 고정 search_path, schema qualification
   - PUBLIC/anon/authenticated/service_role의 EXECUTE 권한과 기존 함수 권한 회수
   - RLS 및 service-role 우회 전제
   - limiter bucket key, window 경계, 동시 요청 원자성, cleanup/성장 한계
   - task claim의 owner/run/attempt/retry/lease 조건과 SKIP LOCKED 동작
   - lease token fencing이 candle/result 쓰기 및 complete/fail 모두에 빠짐없이 적용되는지
   - retry_wait/expired lease/attempt 상한/terminal state의 모순 또는 stuck task 가능성
   - reconciliation의 동시성, 빈 task run, 일부 성공·실패, queued/processing 전이
   - migration 재실행 및 부분 실패 시 복구 가능성
4. 구현 보고서에 기록된 주장과 실제 SQL/호출부가 일치하는지 확인한다. 불일치는 반드시 파일·함수·SQL 객체 이름을 들어 보고한다.
5. DB 접속 없이 실행할 수 있는 read-only preflight SQL 스크립트를 별도 파일로 작성한다. 예: `supabase/preflight/20261114000200_auth_owner_recovery_preflight.sql`.
   - 오직 SELECT / WITH / SHOW / EXPLAIN (ANALYZE 금지) 등 읽기 전용 문장만 포함한다.
   - CREATE/ALTER/DROP/INSERT/UPDATE/DELETE/GRANT/REVOKE/DO/CALL/SET ROLE 금지.
   - 테이블·컬럼·constraint·index·function signature/owner/search_path/ACL·RLS/policies·role 존재·기존 데이터 상태를 확인하는 쿼리를 포함한다.
   - 존재하지 않을 수 있는 객체를 조회해도 스크립트 전체가 중단되지 않도록 catalog 기반으로 작성한다.
   - 민감한 데이터 행 전체를 출력하지 않는다. 개수와 상태별 집계만 조회한다.
   - 스크립트 상단에 읽기 전용임과 실제 실행 전 대상 프로젝트 확인 필요를 명시한다.
6. 별도 문서 `reports/2026-11-14-migration-static-review.md`를 작성한다.
   - 각 검토 항목을 PASS / WARNING / BLOCKER로 구분
   - blocker가 있으면 DB 적용 금지로 결론
   - 적용 전 필수 조건, 예상되는 기존 데이터 영향, rollback 한계, 운영 백업 필요성 명시
   - preflight SQL의 실행 순서와 결과 해석법 제공
   - migration 적용 자체는 승인/실행하지 않았다고 명시
7. `handover/STATUS.md`를 갱신한다. 구현 보고서와 상충하지 않게 최신 상태와 다음 단계를 명확히 한다.

## 완료 보고

- 작성/수정 파일 목록
- 정적 검토 결과 및 blocker
- preflight SQL이 읽기 전용인지 자체 재검토한 결과
- 원격 DB 접속/쿼리 및 migration 실행을 하지 않았다는 확인
- 기존 working tree를 수정·stage·commit하지 않았다는 확인
- 다음 단계 권고

## 완료 기준

- 신규 migration의 보안 및 데이터 호환 위험을 구체적으로 평가
- read-only preflight SQL 스크립트 준비
- blocker가 있으면 해결 전까지 적용 금지 명시
- 원격 DB 및 비밀정보에 전혀 접근하지 않음
