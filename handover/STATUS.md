# 프로젝트 진행 상태

**기준일:** 2026-11-14
**코드 프로젝트:** `C:\Users\PC1\ai-trading-scanner`
**코드 저장소:** 현재 작업 기록 기준, 문서 저장소와 별도 관리

## 현재 단계

수동 실행형 탐색기의 분석 흐름과 화면/API 코드는 구현되어 있습니다. Supabase 환경 구성과 마이그레이션 적용이 되지 않아 전체 분석의 영속 저장 end-to-end 검증은 아직 완료되지 않았습니다.

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

## 최근 검증 결과

- `npm.cmd run build`: 종료 코드 0
- Production 서버의 `/api/markets`: HTTP 200, 2,107개 반환, 거래소별 758/528/821개, 누락 가격 0
- 반환 시장 USDT 선형 필터 위반: 0
- BTC/ETH 가격: 세 거래소 모두 확인
- 메인 화면: HTTP 200, 분석 시작 버튼 표시. 초기 화면에 자동 시장 API 호출 없음
- Supabase가 미설정된 상태의 `/api/analysis/start`: HTTP 503으로 안전하게 중단
- CCXT 공개 OHLCV 호출 방식으로 3개 거래소 × 1h/4h/1d에서 500개 조회를 확인한 기록이 있음. 다만 현 코드의 DB 캐시/저장 통합은 실제 Supabase에서 검증되지 않음
- 문서 저장소 작업에서는 코드 빌드를 실행하지 않음. 위 빌드 결과는 직전 코드 작업 결과임

## 미완료 / 주의 사항

1. 전용 Supabase 프로젝트에서 SQL migration을 검토·적용해야 합니다. 스키마 변경은 사용자 승인이 필요한 작업입니다.
2. `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`를 승인된 로컬/Vercel 비밀 환경변수에 설정해야 합니다. 비밀값을 Git에 저장하지 않습니다.
3. Supabase 연결 후 `maxCandidates=1` 등 작은 규모로 start → step → status → results, 캔들 저장, 중복 upsert를 end-to-end 확인해야 합니다.
4. Vercel 공개 전에 분석 API 접근 제어를 설정해야 합니다. 서버는 service role을 사용하므로 무인증 공개 상태로 배포하지 않습니다.
5. 원형파·후잔잔의 상세 판정 규칙은 미정입니다. 사용자 확정 규칙을 받은 뒤에만 신호 로직에 반영합니다.
6. 후보 거래량 변화는 1h 캔들로 확인하는 후속 지표이며, 24h ticker만으로 계산하지 않습니다.

## 다음 작업 순서

1. 전용 Supabase 연결 및 SQL 적용 승인/준비
2. 환경변수 설정 후 소수 종목 end-to-end 테스트
3. 재시도, 작업 lease 회복, 동시성 및 실패 거래소 분리 검증
4. 배포 전 분석 API 인증·접근 제한 구성
5. 확정된 파동 규칙을 `decisions/`에 기록한 후 선택적으로 구현

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
