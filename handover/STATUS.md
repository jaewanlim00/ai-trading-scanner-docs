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
