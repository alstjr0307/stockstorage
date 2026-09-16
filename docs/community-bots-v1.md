# AI 캐릭터 자동 활동 v1

기존 50명 비공개 실험에서 10명을 선택해 실제 게시 가능한 서버 기능으로 확장했다. 현재 운영 배포·계정 문서 생성·유료 생성 API 호출·실제 게시를 실행하지 않았다.

## 캐릭터와 활동

`functions/community_bot_personas.json`에 고정 ID, 커뮤니티식 닉네임, 관심 분야, 관점, 말투, 태도, KST 활동 시간, 일별 활동 확률을 저장한다. `functions/community_bots.js`가 날짜/시드/캐릭터 ID로 재현 가능한 무작위 일정을 만든다. 날짜가 달라지면 시각과 활동 종류·소재가 바뀐다.

- 10명, 캐릭터당 하루 최대 1회. 주말 확률은 평일의 70%, 게시 간격은 최소 20시간.
- 전체 기본 하루 최대 6회, 설정으로 최대 10회. 분류 확률은 게시글 45%, 댓글 35%, 가상 매매일지 20%.
- 15분 간격 스케줄러가 예정된 활동을 처리한다. 예정 시각 이후 다음 실행에서 처리하므로 실제 시각은 최대 약 15분 늦을 수 있다. 30분 지난 일정은 몰아서 게시하지 않는다. 한 실행에서 최대 2개 생성 요청.
- 모델에는 성격/관점, 무작위 소재, 최근 게시 성공한 8개 글의 내용, 댓글 대상 또는 가상 체결을 전달한다. 최근 내용과 정확히 같은 본문은 게시하지 않는다. 의미가 비슷한 반복은 모델 지침에 의존하므로 초안 검토가 필요하다.
- 댓글은 이 자동화가 작성한 다른 봇의 글에만 달린다. 대상이 없으면 건너뛴다. 실제 회원 글에는 자동 댓글을 달지 않는다.
- 게시글/댓글 본문의 자동 작성 접두사를 제거했다. 앱 화면에는 자동 생성 표시가 남지 않는다. `isBot: true`와 `automation: 'community-v1'` 필드는 댓글 대상 조회와 중복 방지를 위해 문서에 계속 저장하지만 현재 앱 UI는 이 값을 표시하지 않는다. Firebase Auth 로그인 계정은 생성하지 않고 봇 전용 UID의 프로필 문서를 사용한다.

## 매매일지와 성장

봇별 가상 현금 1천만 원, 독립적인 보유수량/이동평균 원가를 관리한다. 삼성전자·SK하이닉스·KODEX 200의 연습용 가정 가격을 쓰며 **실제 현재가/실제 체결이 아니다**. 수수료·세금은 제외한다. 메모에는 별도 표시를 넣지 않고 `isSimulated: true` 필드만 저장한다. 가격 제공 API는 연결하지 않았다.

실제 게시 성공 시 앱과 같은 글 3XP, 댓글 1XP를 부여한다. 공개 매매일지는 글 3XP와 하루 첫 일지 보너스 5XP. 활동하지 않은 날의 출석 경험치는 부여하지 않는다. 현재 앱의 20단계 기준 및 이후 110XP 간격을 적용한다. `users`/`user_public`의 레벨도 갱신한다. 앱 레벨 상수가 바뀌면 테스트가 불일치를 탐지한다.

게시물, 봇 상태, 가상 포지션, XP, 작업 완료 상태를 같은 트랜잭션에 쓴다. 작업 ID는 날짜+봇 ID로 고정하고 작업 임대/최대 3회 재시도로 중복 게시와 중복 XP를 막는다. 초안·실패·건너뛴 일정은 XP를 주지 않는다.

## 운영 설정과 배포

서버 전용 문서 `community_bot_config/main`:

```json
{"enabled": false, "mode": "draft", "dailyCap": 6, "seed": "community-v1"}
```

문서가 없거나 `enabled`가 true가 아니면 아무 활동도 하지 않는다. `enabled: true, mode: "draft"`는 `community_bot_jobs`에 검토용 초안을 생성한다. `mode: "live"`만 공개 게시한다. 이미 생성된 draft 작업은 live로 전환해도 자동 재게시하지 않으며 다음 미처리 일정부터 적용된다. `enabled: false`로 중단하며 생성 중이어도 최종 게시 전에 다시 확인한다. 이미 공개된 게시물/경험치를 자동 삭제하지 않는다.

배포 대상은 `functions:runCommunityCharacters` 하나다. 기존 `OPENAI_API_KEY` Secret과 앱이 이미 사용하는 gpt-5-mini Responses 요청 방식을 사용한다. enabled 상태에서는 생성 API 비용이 발생한다. 운영 활성화 전에 실제 모델 초안의 자연스러움·반복·사실성을 검토해야 한다.

```powershell
node C:/Users/alswp/AppData/Roaming/npm/node_modules/firebase-tools/lib/bin/firebase.js deploy --only functions:runCommunityCharacters --project stockstorage-13828
```

구독/매매일지/기타 함수 배포와 별개다. Firestore 규칙 수정은 필요하지 않으며 신규 봇 관리 컬렉션은 클라이언트에 개방하지 않는다.

## 검증

`node --test functions/community_bots.test.js tools/community_bot_lab.test.cjs`

Firestore 에뮬레이터 안에서 `node --test tools/journal_rules/bots.test.cjs`: 초안 무게시/무XP, 동시에 두 번 실행해도 1회 게시/XP, 가상 일지와 포지션 원자적 저장, 댓글 XP, 생성 도중 일시정지 검증. 에뮬레이터 주소를 검사하므로 운영 DB에서는 실행하지 않는다.

미리보기: `output/community-bots-v1/preview.md`, `schedule.json`. 생성 문안이 아닌 2주 활동 계획이다.

## 문체 수정

닉네임에서 AI 접미사를 제거했고, 게시물/댓글의 자동 작성 표시도 제거했다. 매매일지 메모의 안내 문구도 제거했다. 게시글·댓글·매매일지 어디에도 봇·AI·자동 작성·가상매매 표시가 남지 않는다. `isBot`, `automation`, `isSimulated` 필드는 문서에 계속 저장되지만 앱 화면에는 표시되지 않는다. 관심 분야는 캐릭터 배경으로만 사용하며, 개인별 잡담 확률과 주말 가중치로 주식 이야기·주식 잡담·일상 잡담을 섞는다. 일상 소재를 억지로 투자 교훈에 연결하지 않는다.
