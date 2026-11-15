# 통합 작업 05 — 후보 캔들 차트 API 및 상세 시각화

**작성일:** 2026-11-15  
**대상 코드 프로젝트:** `C:\Users\PC1\ai-trading-scanner`  
**문서 저장소:** `jaewanlim00/ai-trading-scanner-docs`  
**작업 방식:** 한 번의 통합 지시로 전체 범위를 수행하되, 내부 구현 순서와 테스트는 단계별로 진행  
**도구 운영:** GPT Work와 Antigravity를 병행하되 동일 working tree를 동시에 수정하지 않는다. 한 도구의 편집·테스트가 끝난 뒤 다른 도구는 독립 검토에만 사용한다.

## 목적

저장된 분석 기록에서 후보/롱·숏 결과를 선택하면 해당 run에 속한 종목의 저장 캔들을 안전하게 조회하고, Lightweight Charts로 캔들 및 RSI를 확인할 수 있게 한다. 이번 작업은 분석 결과를 투명하게 보여주는 UI/API 단계이며, 매매 신호나 후보 선정 알고리즘을 바꾸지 않는다.

## 작업 전 필수 확인

1. 이 문서, `instructions/WORKFLOW.md`, 최신 `handover/STATUS.md`, `reports/2026-11-15-run-history-delete-chart-readiness.md`를 읽는다.
2. 코드 프로젝트의 현재 branch, `git status --short`, 최근 변경, package 상태를 기록한다.
3. 기존 사용자 변경/미추적 파일, `data/scanner.sqlite`, `.env.local`, 체크포인트를 열람·초기화·삭제·덮어쓰기하지 않는다. DB와 비밀값은 보고서에 내용을 기록하지 않는다.
4. 현재 프로젝트가 SQLite 로컬 단일 사용자 전용임을 유지한다. Supabase로 되돌리거나 클라우드/다중 사용자 구조로 바꾸지 않는다.

## 승인된 구현 범위 — 이번 통합 작업에서 수행

### A. run 소유권을 확인하는 캔들 API

- `GET /api/analysis/candles`를 추가한다.
- query 계약은 `runId`, `exchange`, `symbol`, `timeframe`으로 한다. 기존 코드의 실제 ID/심볼 규칙을 확인하고 일치시킨다.
- 로그인 세션을 검증하고, run이 현재 사용자 소유인지 확인한다.
- 해당 run의 후보 목록에 exchange+symbol 조합이 실제 포함되어 있는지 확인한 뒤에만 캔들을 읽는다. run 소유권만으로 임의 심볼/공유 candle cache를 조회할 수 없어야 한다.
- timeframe은 기존 타입에서 허용하는 `1h | 4h | 1d`만 허용한다. run ID 및 기타 입력을 엄격히 검증하고, 결과 수는 기존 저장 함수의 안전한 한도(최대 500개 권장)를 넘지 않게 한다.
- 종료된 캔들만 시간 오름차순으로 반환한다. 비밀값·파일경로·내부 오류 stack은 응답에 노출하지 않는다. 민감 응답은 기존 no-store 정책을 따른다.
- 기존 auth, Origin, local rate limit 패턴을 재사용한다. GET에 불필요한 Origin 요구를 새로 만들지 말고 기존 API 관례와 일치시킨다.

### B. 차트 UI

- 이미 설치된 `lightweight-charts`만 사용한다. package.json/package-lock 변경, 새 패키지 설치 금지.
- Next.js SSR과 충돌하지 않도록 차트 라이브러리의 브라우저 전용 초기화/동적 import 방식을 기존 앱 구조에 맞게 사용한다.
- 기존 결과/후보 화면에 차트 진입점을 추가한다. 후보 또는 롱·숏 결과를 선택하면 선택 상태가 명확히 표시되고 해당 종목 차트를 불러온다.
- 거래소/심볼/시간봉 선택을 지원한다. 기본 시간봉은 `1h`; 선택 가능한 값은 `1h`, `4h`, `1d`.
- 캔들 차트와 RSI(14) 보조 시각화를 제공한다. RSI는 차트 표시용 계산이며 기존 분석 결과 점수/qualified 판정에 영향을 주지 않는다.
- 로딩, 빈 캔들, API 오류, 선택 후보 없음, 거래소/심볼/시간봉 변경 시 이전 데이터 제거를 처리한다.
- 컴포넌트 unmount 때 chart/listener/observer를 정리하고, 컨테이너 크기 변경에 반응한다.
- 좁은 화면에서도 차트가 넘치지 않도록 반응형으로 만든다.
- 기존 저장 기록 불러오기/이어하기/삭제, 로그인, 분석 시작 및 진행 화면을 회귀시키지 않는다.

### C. 분석 근거 확장 설계 문서

- 현재 저장되는 pivot/trendline 값이 boolean 중심이라 차트 overlay 좌표가 부족하다는 점을 코드와 대조한다.
- 다음 단계용 evidence record 계약을 보고서에 제안한다. 최소 필드: run/candidate 식별자, exchange/symbol, timeframe, evidence kind, 기준 candle timestamp, 기준 가격, start/end anchor 좌표, line slope 또는 계산값(해당할 때), 평가 candle timestamp/close, 판정값, reason code, algorithm version.
- 이번 작업에서는 evidence DB table/schema/migration/API write path를 만들지 않는다. 갠각·원형파·후잔잔 판정 로직도 추가하지 않는다. 확정되지 않은 규칙은 미정으로 남긴다.

## 검증 범위

1. 캔들 API: 정상 run+후보, 다른 run/없는 후보, 잘못된 UUID, 잘못된 timeframe, 로그아웃 상태, 빈 캔들, 500개 상한.
2. 권한/정보노출: run owner mismatch 및 후보 mismatch는 정보 존재 여부를 과도하게 드러내지 않는 동일한 not-found 계열 처리. 임의 exchange/symbol로 shared candle cache를 조회할 수 없는지 확인.
3. 차트 데이터: timestamp 정렬, 종료 캔들만 표시, OHLC 유효성, null volume 처리, RSI warm-up 구간.
4. UI: 후보 선택, 시간봉 전환, 재선택 시 이전 차트 제거, 로딩/오류/빈 상태, 작은 화면, 컴포넌트 정리.
5. 회귀: 기존 history load/resume/delete, login, analysis start/step/status/results.
6. 프로젝트의 기존 검사 실행: `npm.cmd test`, `npm.cmd run lint`, `npx.cmd tsc --noEmit`, `npm.cmd run build`, `git diff --check`.
7. 브라우저 자동화 도구가 이미 설치되어 있으면 수동 UI 검증을 수행한다. 새 테스트/브라우저 패키지 설치가 필요하면 설치하지 말고 미실행 사유를 보고한다.
8. 가능한 경우 실제 API/화면을 로컬에서 검증하되, 실제 사용자 DB의 기존 run/candle/result를 삭제·수정하지 않는다. 테스트는 격리된 임시 SQLite DB를 사용한다.

## 명시적 제외 및 승인 경계

- 분석/랭킹/롱·숏 scoring, RSI 신호 해석, 후보 선정 임계값 변경 금지.
- 갠각, 원형파, 후잔잔 규칙을 추측해 구현 금지.
- SQLite schema/migration 변경, 실제 사용자 DB 데이터 변경·삭제·초기화 금지.
- 환경변수/비밀값/로그인 비밀번호 변경 금지.
- package 설치/제거/버전 변경 금지.
- 외부 서비스, Vercel, Supabase, 배포, 인터넷 공개 변경 금지.
- 자동주문, 거래소 API key 사용, cron/자동 감시 금지.
- 사용자 기존 변경사항을 stage/commit하지 않는다. 코드 저장소 커밋은 별도 지시가 있을 때만 한다.

## 완료 산출물

1. 구현 보고서 `reports/YYYY-MM-DD-candlestick-chart-api-ui.md`.
2. `handover/STATUS.md` 갱신: 완료 범위, 변경 파일, 테스트 결과, 미실행 검증, 미해결 항목, 다음 단계.
3. 증거 저장 계약과 갠각/원형파/후잔잔 미정 사항을 명확히 기록.
4. 마지막 보고는 실제 실행 결과만 완료로 표시하고, 미실행은 미실행으로 표시한다.
5. 문서 변경은 이 지시서와 handover/report 범위로 제한한다. 문서 저장소 main 반영은 해당 문서 파일만 포함한다.
