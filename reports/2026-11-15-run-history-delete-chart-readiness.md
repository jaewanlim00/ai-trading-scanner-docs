# 저장 분석 기록 삭제 및 차트 시각화 사전 조사

**작성일:** 2026-11-15  
**코드 프로젝트:** `C:\Users\PC1\ai-trading-scanner`  
**범위:** 저장된 분석 기록 개별 삭제 기능 구현, 차트 데이터/화면/분석 근거 조사

## 변경 사항

### 기록 삭제

- `app/api/analysis/history/route.ts`에 인증 세션·요청 Origin 검증·기존 분석 결과 요청 제한을 적용한 `DELETE` 처리기를 추가했습니다.
- run ID는 UUID 형식만 허용하고, 저장 계층에서 현재 단일 사용자 owner 조건으로 다시 검사합니다. owner가 다르거나 기록이 없으면 같은 `not_found` 결과로 처리합니다.
- SQLite 트랜잭션에서 기록 상태를 확인한 뒤 `completed`, `completed_with_errors`, `failed`만 삭제합니다. `screening`, `queued`, `processing`은 `active`로 거절해 작업 중 실행을 보호합니다.
- `scanner_runs` 삭제 시 외래키 `ON DELETE CASCADE`를 따라 해당 run의 `scanner_candidates`, `scanner_tasks`, `scanner_results`만 삭제됩니다. 관련 FK와 실행 상태 검사는 같은 트랜잭션 안에서 이루어집니다.
- `scanner_candles`는 run 외래키가 없고 `(exchange, symbol, timeframe, timestamp_ms)`로 전 실행이 공유하는 캐시이므로 삭제 대상에서 제외합니다. 따라서 다른 기록이 재사용하는 캔들 데이터를 보존합니다.
- `app/page.tsx`의 저장 기록 행에 개별 확인창과 삭제 버튼을 추가했습니다. 진행 중인 기록의 버튼은 비활성화됩니다. 삭제 성공 시 기록 목록에서 즉시 제거하고, 그 기록이 현재 화면에 선택된 경우에만 해당 상세 표시 상태를 비웁니다. 기록 불러오기 및 수동 이어하기 동작은 유지됩니다.
- 별도 요청 제한 값을 새로 만들지 않고 기존 `analysis_results` 제한 경로를 재사용했습니다. DELETE 요청은 Origin 검증을 요구합니다.

### 변경 파일

- `app/api/analysis/history/route.ts`
- `app/page.tsx`
- `lib/scanner/storage/sqlite.ts`
- `lib/scanner/storage/index.ts`
- `tests/scanner-storage.test.mjs`

package 파일, 환경변수, 분석 알고리즘, SQLite schema/migration, 실제 DB의 기존 기록은 변경하지 않았습니다. 코드 변경은 커밋하지 않았습니다.

## 삭제 기능 검증

격리된 임시 SQLite 경로를 사용하는 자동 테스트로 다음을 확인했습니다.

- 완료된 run 삭제 후 run, 후보, 작업, 결과가 cascade 삭제되고 재시작 후에도 삭제 상태가 유지됨
- 진행 중인 run 삭제가 `active`로 거절됨
- 다른 run이 진행 중인 task를 삭제 뒤 정상 완료하고 결과를 저장함
- 같은 캔들 캐시가 삭제 뒤에도 남음
- 다른 owner의 run 삭제 요청이 `not_found`로 처리됨

실제 `data/scanner.sqlite`의 사용자 기록은 열람하거나 삭제하지 않았습니다. 브라우저에서 클릭하는 수동 UI 검증은 수행하지 않았습니다.

## 검증 결과

| 검사 | 결과 |
|---|---|
| `npm.cmd test` | 통과, 12/12 |
| `npm.cmd run lint` | 종료 코드 0 |
| `npx.cmd tsc --noEmit` | 종료 코드 0 |
| `npm.cmd run build` | 종료 코드 0 |
| `git diff --check` | 오류 없음 |

빌드 산출물에 `/api/analysis/history` 동적 route가 포함되는 것을 확인했습니다. 사용자의 기존 미커밋 코드 상태를 보존했으며, 이번 코드 변경은 stage/commit하지 않았습니다.

## 현재 차트 데이터 및 화면 구조

### 캔들 저장/조회

- 타입: `lib/scanner/types.ts`의 `Candle`에는 거래소, CCXT 심볼, `1h | 4h | 1d`, millisecond timestamp, OHLC, nullable volume, `isClosed`, `fetchedAt`가 있습니다.
- 저장: `lib/scanner/storage/sqlite.ts`의 `scanner_candles`는 고유키 `(exchange, symbol, timeframe, timestamp_ms)`를 사용합니다. `fetchCandles()`는 선택 후보의 기존 종료 캔들을 재사용하며 최신 데이터만 요청하고, task 완료 트랜잭션에서 캔들과 양방향 결과를 저장합니다.
- 조회: `readCandles(exchange, symbol, timeframe, limit=500)`는 종료 캔들만 가져오고 timestamp 오름차순으로 반환합니다. 최대 요청은 1,000개입니다. 현재 이 읽기 함수는 내부 저장 계층에 있으며 브라우저용 캔들 API는 없습니다.
- 결과 화면: 롱/숏 결과와 1차 후보 목록은 표시하지만 행은 현재 클릭 가능한 차트 진입점이 아니며 차트 컴포넌트도 없습니다. RSI 숫자와 분석 근거 문자열은 카드에 있습니다.

### 차트 도입 계획

기본 라이브러리 `lightweight-charts`가 이미 `package.json`에 `^5.3.0`으로 선언되어 있습니다. 이번 단계에서 의존성 변경은 하지 않았습니다. 공식 v5 API는 캔들/선 시리즈와 별도 series-marker primitive를 제공하며 custom series/primitives로 차트 오버레이를 확장할 수 있습니다. 현재 공식 release 페이지에서는 v5.3.0을 최신으로 표시합니다.

- 1단계: 로그인과 run owner를 검사하는 `GET /api/analysis/candles?runId=…&exchange=…&symbol=…&timeframe=…`을 추가합니다. run이 해당 사용자 소유인지와 종목이 그 run의 후보인지 먼저 확인하고, 시간봉을 허용 목록으로 검증한 뒤 종료 캔들만 반환합니다. 전체 공유 캔들 저장소를 임의 심볼로 조회하는 API는 만들지 않습니다.
- 2단계: 클릭한 롱/숏 결과 또는 분석 후보를 선택 상태로 두고, 위 API로 해당 캔들만 읽는 클라이언트 차트 컴포넌트를 추가합니다. `useEffect`에서 차트를 만들고 unmount에서 정리하며 크기 변경을 반영합니다. 거래소/심볼/시간봉 선택 상태는 컴포넌트 입력으로 분리합니다.
- 3단계: 캔들부터 표시한 뒤, RSI 14는 별도 아래 pane 또는 보조 표시로 추가합니다. 기존 분석의 점수나 판정 기준은 시각화 작업에서 변경하지 않습니다.
- 4단계: 실제 분석 증거를 저장하는 schema/API 계약을 확정한 뒤 고점·저점 marker, 추세선 segment, 종가 이탈/돌파 marker, 사용자 확정 갠각, 갠각 이탈 및 추세 확장 annotation을 추가합니다. 분석 엔진이 계산한 근거만 그립니다.
- 시간축은 원본 timestamp를 기준으로 하며, 각 overlay는 자신의 기준 시각/가격 좌표와 timeframe을 함께 전달합니다. 거래소와 심볼이 바뀌면 이전 차트 및 overlay를 즉시 비웁니다.

공식 기술 참고:

- [Lightweight Charts v5.3.0 release](https://github.com/tradingview/lightweight-charts/releases)
- [v4에서 v5로의 시리즈/marker API 변경 안내](https://tradingview.github.io/lightweight-charts/docs/migrations/from-v4-to-v5)
- [Series markers 예제](https://tradingview.github.io/lightweight-charts/examples/markers-and-lines/series-markers)
- [Custom series 및 시각화 확장](https://tradingview.github.io/lightweight-charts/docs/plugins/custom_series)

기본 라이브러리로 첫 번째 캔들·선·marker 시각화가 가능해 보이므로 현재 범위에서는 추가 패키지가 필요하지 않습니다. 추후 공식 plugin 등 별도 패키지가 필요해지면 기술 선택과 설치 승인을 먼저 받습니다.

## 분석 근거 투명성 조사

현재 결과가 저장하는 근거:

- 후보 표: 1차 선정/제외 이유 문자열, 24시간 시장 snapshot, 추세/변곡 점수, 순위, 후속 데이터 확인 항목
- 방향 결과: 롱/숏별 점수·qualified 여부·reason 코드와 timeframe 분석 JSON
- timeframe 결과: RSI 14, 최근 종가와 시각, range position, 고점/저점 방향 관계, 추세선 돌파 boolean, 최근 pivot boolean, 변동 압축비, 방향별 점수·이유
- 실행 이력: 분석 설정, 거래소 수집 상태, 후보/작업 수, 진행/완료/실패 정보

차트 오버레이나 수치 근거로 쓰기에는 아직 부족한 부분:

- pivot의 실제 가격 및 candle timestamp/index 목록이 저장되지 않습니다. `recentPivotHigh/Low`는 boolean만 남습니다.
- 추세선 기준 고점·저점의 좌표, 기울기, 계산 구간, 평가 캔들의 선상 가격/실제 종가 차이가 남지 않습니다. 결과에는 방향별 돌파 여부와 reason만 있습니다.
- 갠각 계산·기준 변곡점·각도/기울기·이탈 근거는 구현되어 있지 않고 저장되지 않습니다.
- 원형파/후잔잔 규칙은 실제 실행되지 않습니다. JSON 규칙은 저장되며 상태만 `unconfigured` 또는 `stored_not_executed`로 기록됩니다.
- 정밀 분석 대상으로 선택되지 않은 후보는 결과 row가 없을 수 있어 방향별 분석 제외 이유/미실행 사유가 구조화되어 있지 않습니다. 1차 제외 이유와 정밀 분석 결과를 구분해 보여야 합니다.
- 현재 결과 API는 qualified 결과만 반환하므로 향후 상세 분석 화면에서 미자격 양방향 점수를 보여주려면 API 계약을 별도로 늘려야 합니다.
- 현재 분석 엔진의 RSI는 timeframe별로 50 위/아래에서 직전 RSI보다 증가/감소하는지를 방향 점수에 보조 가산합니다. 사용자가 향후 참고 기준으로 제시한 RSI 30/70 과매도·과매수 조건은 현재 구현에 없습니다. 이번 단계에서는 요청대로 기존 로직을 변경하지 않았습니다.

따라서 다음 차트 구현 전에 알고리즘 임계값을 바꾸지 않고도 저장할 수 있는 `analysis_evidence` 구조를 설계하는 것이 적절합니다. 예: 실행/run, 후보, timeframe, evidence kind, start/end candle timestamp, anchor price, line slope, evaluation candle/time/price, boolean decision, reason code, algorithm version. 실제 갠각과 원형파의 세부 정의는 사용자 확정이 필요하며 이번 작업에서 임의 판정 규칙을 만들지 않았습니다.

## 미해결 사항

1. 삭제 UI의 실브라우저 수동 클릭 테스트는 미실행입니다. 자동 테스트는 격리된 임시 DB를 대상으로 했습니다.
2. 브라우저 차트, 캔들 API, overlay/evidence 저장은 계획만 작성했습니다.
3. 고점·저점 좌표와 추세선 좌표를 저장하려면 별도 evidence persistence/API 작업이 필요합니다.
4. 갠각의 기준점과 각도 환산 규칙 및 원형파/후잔잔 조건은 사용자와 확정해야 합니다.
5. 실제 DB 사용자 이력은 조회·변경하지 않았습니다.

## 다음 작업 제안

1. 차트 상세 패널의 시간봉 선택, 후보 선택 동작, candle API response 계약 승인
2. 알고리즘 임계값을 건드리지 않는 evidence 저장 형식과 기존 분석 결과 호환 방안 검토
3. 후보 run-owner 보호 API 및 Lightweight Charts 캔들 UI 구현
4. mock/격리 DB 차트 데이터 테스트와 UI 브라우저 검증
5. 갠각/원형파/후잔잔 정의는 기술 규칙이 확정된 뒤 별도 구현

