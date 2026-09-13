> 후속 변경: 아래의 구버전 쓰기 차단/규칙 필수 배포 조건은 철회되었습니다. 현재 동작은 [입력 순서와 구버전 호환](journal-order-compatibility.md)을 따릅니다.

# 매매일지 계산·동시 저장·Firestore 오류 수정

## 수정 범위

디자인과 입력 배치는 변경하지 않았다.

- 차트도 공통 `JournalLedger`를 사용한다. 분할 매도 시 매도 직전 이동평균 원가로 손익을 계산하고, 차트에 선택된 매도가 중복 전달돼도 한 번만 반영한다.
- 거래 시각이 같거나 수량에 모순이 있으면 `effectFor`가 확정 계산 결과를 내주지 않는다. 보유 현황, 매도 카드, 차트의 확정 손익 표시를 제한한다.
- 계정별 `journal_revisions/{uid}`의 revision과 거래 변경을 하나의 트랜잭션에 기록한다. 검증할 거래 목록을 읽기 **전에** revision을 읽는다. 다른 기기가 선행 저장하면 전체 목록을 다시 읽어 검증한다. 보안 규칙이 충돌을 permission-denied로 반환하는 경우에도 revision이 실제 증가했을 때만 재검증한다.
- 기존 Firestore 플랫폼 인터페이스 6.6.12를 로컬 경로로 고정하고, 트랜잭션 완료 경합만 보정했다. SDK 전체 버전 업그레이드나 전역 오류 무시는 하지 않았다. 원래 트랜잭션 실패는 호출자에게 전달된다.

SDK 패치 근거와 라이선스는 `third_party/cloud_firestore_platform_interface/PATCH.md` 참조.

## 배포 조건 — 아직 운영에 적용하지 않음

앱 코드만 설치하면 운영의 기존 규칙에는 `journal_revisions` 접근 권한이 없어 거래 저장이 실패한다. 새 APK/웹과 `firestore.rules`를 함께 적용해야 한다. 규칙을 적용한 뒤에는 이전 프로토콜을 쓰는 구버전의 거래 생성·금액/수량 변경·삭제가 거부된다. 조회, 메모·공개 여부 변경 및 좋아요는 기존 권한을 유지한다.

프로덕션 적용 시 업데이트 안내/필수 업데이트 정책과 배포 순서를 함께 결정해야 한다. 검증을 우회하는 구버전 쓰기를 허용하면서 동시 매도 안전성까지 보장할 수는 없다.

규칙만 배포할 명령: `firebase deploy --only firestore:rules` (현재 작업에서 실행하지 않음).

기존 거래의 일괄 재저장·마이그레이션은 없다. 최초 저장 때 revision 문서가 추가된다. 에뮬레이터 테스트는 `demo-journal` 프로젝트만 사용했으며 운영 DB에 쓰지 않았다.

## 검증

`flutter test --no-pub test/firestore_transaction_race_test.dart test/journal_logic_regression_test.dart test/journal_v2_test.dart test/journal_original_ui_test.dart`

오류 재현 테스트는 Dart 핸들러가 실패하고 네이티브 처리를 기다리는 중에 네이티브 오류를 전달한다. 이후 대기를 해제해도 Future 중복 완료가 발생하지 않는지 검사한다.

보안 규칙/동시 쓰기 테스트:

1. `npm ci --prefix tools/journal_rules`
2. Java가 PATH에 있는 환경에서 `firebase emulators:exec --config firebase.journal-test.json --project demo-journal --only firestore "node --test tools/journal_rules/rules.test.cjs"`

구버전 쓰기 거부, 메모/공개/좋아요 권한 유지, 오래된 revision 거부, 복수 거래 우회 차단, 두 기기 동시 쓰기, 전량 매도 중 한 건만 저장되는 흐름을 실제 Firestore 에뮬레이터에서 검증한다. 실제 Android 기기에서의 재현·설치 검증은 별도다.

## 롤백

이번 수정은 계산 파일, 저장소, 규칙, 의존성이 묶여 있다. `python tools/rollback_journal_logic.py`로 먼저 검사하고 `--apply`로 함께 복원한 뒤 `flutter pub get` 및 앱 재빌드를 한다. 이후 별도 수정이 있으면 체크섬 검사로 덮어쓰기를 중단한다. 백업은 `output/journal-logic-backup/20260913-010900`에 있다.

운영 규칙을 이미 배포했다면 소스 복원만으로 규칙이 돌아가지 않는다. 복구할 규칙을 별도로 재배포해야 한다. 저장된 거래와 revision 문서는 롤백 스크립트가 삭제하거나 수정하지 않는다. 이번 수정이 적용된 상태에서 이전 `rollback_journal_v2.py`로 진입 파일만 되돌리는 것은 지원하지 않는다.

## 추가 수정: 기록 편집과 날짜별 메뉴

- 저장 버튼을 누른 시점의 입력값을 고정하고 저장 중 입력을 막는다. 기존 ID, 작성자, 작성일, 좋아요, 종목 코드 및 연결 정보는 유지한다.
- 수정된 거래를 포함한 해당 종목의 전체 이력을 검증한다. 이후 매도를 초과하게 만드는 수량 축소와 날짜 이동은 차단한다. 과거 가격 변경은 카드와 차트의 공통 원장으로 손익을 재계산한다.
- 응답 유실 후 같은 수정을 재시도하면 서버 값이 원하는 값과 정확히 일치하는 경우 완료로 처리한다. 다른 수정과의 충돌은 덮어쓰지 않는다. 분석 로그 오류는 거래 저장 실패로 취급하지 않는다.
- 물타기·불타기·동일가 추가 매수를 모두 ‘추가매수’로 표시한다. 날짜별 메뉴에 추가매수와 매도를 연결했다. 청산된 매수 기록도 수정할 수 있으며 보유수량이 없거나 이력이 불확실하면 매도 메뉴를 비활성화한다.
- 이번 변경만 되돌리기: `python tools/rollback_journal_edit.py`로 검사 후 `--apply`. 백업은 `output/journal-edit-backup/20260913-013137`. 이전 계산/트랜잭션 수정까지 되돌릴 경우 이번 변경을 먼저 롤백하고 기존 `rollback_journal_logic.py`를 실행한다. 저장 데이터와 운영 규칙에는 직접 접근하지 않는다.
- 검증: `test/journal_edit_test.dart`에 과거 수정 재계산, 날짜/수량 검증, 동일 수정 재시도, 실제 입력폼의 저장 중 닫기, 실제 날짜별 메뉴 회귀 테스트 추가. 운영 배포는 수행하지 않았다.
