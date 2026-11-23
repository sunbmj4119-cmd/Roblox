# ☄️ Meteor Miners

광석을 캐고, 펫을 뽑고, **7분마다 떨어지는 운석을 서버 전체가 쟁탈**하며 **매주 리셋되는 랭크**에서 경쟁하는 로블록스 채굴 시뮬레이터입니다.

- 📈 [01. 로블록스 인기 게임 & 수익화 분석](docs/01_시장분석.md)
- 🎮 [02. 게임 기획서 (코어 루프, 경쟁, 수익화, 밸런스, 로드맵)](docs/02_게임기획서.md)
- 💵 [03. 가입 · 게임 올리기 · 정산 가이드](docs/03_가입_출시_정산_가이드.md)
- 📊 [04. 현실적인 수익 전망 & 스튜디오 기본 세팅](docs/04_수익전망_스튜디오세팅.md)

맵, 펫, UI까지 **모두 코드로 생성**되므로 3D 에셋 없이 바로 플레이할 수 있습니다.

---

## 🚀 빠른 시작

### 방법 A: 플레이스 파일 바로 열기 (가장 쉬움)
1. 저장소에 포함된 `MeteorMiners.rbxlx`를 Roblox Studio에서 엽니다.
2. **Play** (F5)를 누르면 끝입니다.
3. 코드를 고친 뒤에는 [Rojo](https://rojo.space)로 다시 빌드합니다.
   ```bash
   rojo build default.project.json -o MeteorMiners.rbxlx
   ```

### 방법 B: Rojo 실시간 동기화 (개발용)
1. Studio에 Rojo 플러그인을 설치합니다.
2. 터미널에서 `rojo serve`를 실행합니다.
3. Studio의 Rojo 플러그인에서 **Connect**를 누릅니다.
4. Workspace의 `StreamingEnabled`를 **꺼 주세요** (클라이언트가 게이트와 광석을 직접 참조합니다).
5. 기본 템플릿(Baseplate)에서 시작했다면 기본 `Baseplate`와 `SpawnLocation`은 삭제하세요. 맵은 서버가 시작할 때 자동으로 생성됩니다.

### Studio 테스트 팁
- **Game Settings → Security → Enable Studio Access to API Services**를 켜면 DataStore 저장과 리더보드가 동작합니다. 꺼져 있어도 임시 데이터로 플레이할 수 있습니다.
- 상품 ID가 `0`인 상태에서는 **Studio에서 구매가 즉시 시뮬레이션됩니다** (`[TEST]` 표시). 모든 결제 흐름을 실제 상품을 만들기 전에 테스트할 수 있습니다.
- 화면 왼쪽 아래 **🛠 DEV** 버튼(Studio에서만 보임)으로 코인·젬·랭크 점수·시즌 XP를 지급하고, 운석을 즉시 소환하고, 별/조각을 테스트하고, 데이터를 초기화할 수 있습니다. 라이브 서버에서는 서버가 차단합니다.
- 운석이 빨리 보고 싶다면 DEV → Meteor를 누르거나 `Config.Meteor.IntervalSeconds`를 줄이세요. 서버 시작 후 첫 운석은 최대 150초 뒤에 떨어집니다.
- 설정 검증: [Lune](https://lune-org.github.io/docs)을 설치한 뒤 `lune run tests/ConfigCheck.luau`를 실행하면 펫·광석·상품 이름 오타와 확률 합계를 검사합니다.
- 번역 검증: `python3 tests/lang_keys.py`(코드의 모든 문구가 `src/shared/LangKO.luau`에 있는지 + `%s`/`%d` 순서 일치)와 `lune run tests/LangCheck.luau`(실제 포맷 동작). `tools/publish.sh`는 이 검사가 실패하면 게시하지 않습니다.

### 🌐 언어 (한국어 / English)
- 모든 문구는 영어 원문을 키로 쓰고 `src/shared/LangKO.luau`에서 한국어로 바꿉니다. 로블록스 언어가 한국어인 유저는 자동으로 한국어, 그 외는 영어로 보입니다.
- 게임 안 **⚙️ 설정 → 🌐 언어**에서 자동/한국어/English를 직접 고를 수 있습니다 (저장 후 자동 재접속).
- 새 문구를 추가하면 `python3 tests/lang_keys.py`가 빠진 번역을 알려 줍니다. 한국어 문장에서도 `%s`, `%d`의 **개수와 순서**는 영어와 같아야 합니다.

### ⛏️ 조작 (v8)
- **블록을 터치/클릭** → 캐릭터가 걸어가서 부서질 때까지 계속 캡니다. 조이스틱으로 움직이면 자동 이동이 취소됩니다.
- **폰: 점프 버튼 왼쪽의 큰 ⛏️ 버튼을 누르고 있으면** 가까운 블록을 계속 캡니다 (블록이 멀면 걸어감). PC는 마우스를 누르고 있으면 됩니다.
- 곡괭이는 항상 손에 들려 있습니다 (도구 바 없음).

### 🌠 별 조각 + 🏠 기지 (핵심 루프)
- 40~70초마다 **별이 떨어지고**(빛기둥 표시), 운석을 부수면 조각이 쏟아집니다. 1등은 영웅 이상 조각을 5초간 독점.
- 조각을 주우면 머리 위에 들고 **느려지며, 누구나 때려서 떨어뜨릴 수 있습니다**(스폰 근처 제외). 허브 남쪽 **기지 구역**의 내 기지에 들어가면 진열대에 놓입니다.
- 진열된 조각은 **매초 코인**을 기지 금고에 쌓습니다(오프라인 50%, 최대 2시간). 초록 발판을 밟아 받기, 빨간 발판은 60초 잠금.
- 다른 사람 기지의 조각을 **길게 눌러 훔칠 수** 있고, 주인은 도둑을 때려 되찾습니다(떨어진 조각은 10초 뒤 자동 귀환).
- 진열대 추가 구매(코인), 조각 판매 가능. 수치는 `Config.Shards`, `Config.Base`.
- **서버 인원은 16명**으로 설정하세요(기지 16개, 거리 2개): Creator Dashboard → 게임 → Places → 해당 플레이스 → Server size(최대 인원) = 16. 넘치는 인원은 기지가 빌 때까지 대기합니다. 기지 수는 `Config.Base.Plots`/`Streets`로 바꿀 수 있습니다.

### 🔨 기지 꾸미기 (v10)
- 내 기지(44×44) 안에 서면 **🔨 꾸미기** 버튼 → 카메라가 기지를 내려다봅니다. 아래 카탈로그(기지/자연/가구/조명/장식/바닥/프리미엄)에서 고르고 바닥을 터치해 위치, 🔄 회전, ✅ 설치. 놓인 물건을 터치하면 ✋ 이동 / 🔄 회전 / 🗑 치우기(**100% 환불**이라 자유롭게 바꿀 수 있음).
- **조각 진열대도 장식**입니다(처음 3개 무료, 최대 12개). 가장 좋은 조각이 자동으로 진열되고 나머지는 보관함(📦, 최대 10개)에 들어갑니다.
- **기절 함정**: 도둑을 2.5초 얼리고, 훔쳐 가던 조각을 즉시 돌려보냅니다. **점프 패드**: 밟으면 높이 점프.
- 기지 앞 **❤️ 하트**를 눌러 남의 기지에 하루 1번 좋아요 → 주인은 랭크 점수 + 허브의 **❤️ 베스트 기지** 순위.
- 카탈로그/가격/크기는 `Config.Decor`, 시작 배치는 `Config.StarterBase`.

### 🗿 별의 수호자 + 👟 속도
- 희귀 이상의 별에는 **수호자 골렘**이 지킵니다. 조각을 들면 12초간 쫓아오고, 잡히면 조각을 빼앗아 제자리로 가져갑니다. 수호자를 때리면 2.5초 기절(친구가 도와줄 수 있음).
- 상점 **👟 속도** 탭에서 달리기 속도 업그레이드(최대 +70%).

### 🔥 속도감
- 콤보 12 → **피버**(8초: 광석 2배, 스윙 빠름, 매 타격 충격파, 이동 +20%). 크리티컬은 주변 블록까지 부수는 충격파.
- 길 위의 하늘색 **대시 발판**: 2.5초간 속도 1.7배.
- DEV 메뉴: **Star**(내 앞에 별 떨어뜨리기), **Shard**(조각 바로 들기)로 즉시 테스트.

### 📘 튜토리얼
- 처음 들어온 유저는 화면 위 카드에 **한 번에 하나의 목표**만 봅니다: 광석 8개 캐기 → 곡괭이 구매 → 첫 펫 부화 → 나만의 별을 주워 기지로 (단계마다 보상, 완료 시 젬 100 + 코인 2배 10분). 광석은 부서지는 순간 코인이 됩니다(가방/판매 없음).
- 메뉴 버튼은 튜토리얼 진행에 따라 하나씩 열립니다. 바닥의 빛줄기(가이드)가 다음 목적지를 가리킵니다.
- 다시 보고 싶으면 DEV → Reset (데이터 초기화). 단계와 보상은 `Config.Tutorial`에서 바꿀 수 있습니다.
- 멀티플레이 테스트 (PvP, 운석 경쟁): **Test → Clients and Servers → 2~3 Players → Start**

---

## 📱 폰으로 테스트하면서 업데이트하기 (PC 없이 반복)

게임이 로블록스에 한 번 올라가면, 그다음부터는 **Studio 없이** 새 버전을 올릴 수 있습니다 (Open Cloud Place Publishing API).

1. **최초 1회:** 게임(experience)을 만들어 공개합니다. PC Studio에서 한 번 Publish하거나, 아이폰이라면 Build 앱으로 아무 게임이나 하나 만들어 올려도 됩니다. 그 게임에 이 파일을 덮어씁니다.
2. **API 키 만들기 (폰 브라우저 가능):** Creator Hub → Open Cloud → API Keys → Create API Key
   - Access Permissions: **universe-places** 추가 → 이 게임 선택 → **Write**
   - Accepted IP Addresses: `0.0.0.0/0` (업로드하는 서버 IP가 고정이 아님)
   - 만료일: 30~90일
3. **Universe ID와 Place ID 확인:** Creator Hub에서 게임을 열면 주소창 URL에 숫자로 나옵니다.
4. **배포:** `ROBLOX_API_KEY=키 tools/publish.sh <UniverseId> <PlaceId>`를 실행합니다. Claude 세션에서는 키를 채팅에 쓰지 말고 보안 입력창으로 넣습니다.
5. **확인:** 폰에서 게임을 나갔다가 다시 들어가면 새 버전입니다. 옛 서버가 남아 있으면 Creator Hub의 서버 재시작 메뉴를 쓰세요.

**폰에서 에러 보는 법:** 게임 메뉴 → Settings → **Developer Console → Open** (채팅에 `/console`을 쳐도 됨). 게임 주인은 서버 로그도 볼 수 있습니다. 에러 화면을 **스크린샷으로 보내 주면** 고칠 수 있습니다. Creator Hub → Monitoring → **Error Report**에도 에러가 모입니다.

**오너 테스트 모드** (`Config.OwnerTestMode = true`): 게임 주인에게는 라이브 서버에서도 🛠 DEV 버튼이 보이고, ID가 아직 0인 상품은 **로벅스 차감 없이 테스트 구매**됩니다. 주인 점수는 글로벌 리더보드에 올라가지 않습니다. **정식 오픈 전에 반드시 false로 바꾸세요.**

## 💰 출시 전 수익화 설정 (필수)

1. [Creator Dashboard](https://create.roblox.com/dashboard/creations)에서 게임을 퍼블리시합니다.
2. **Monetization → Passes**에서 게임패스 10개를 만들고, ID를 `src/shared/Config.luau`의 `Config.GamePasses.<이름>.Id`에 넣습니다.
3. **Monetization → Developer Products**에서 상품 16개를 만들고 ID를 `Config.Products.<이름>.Id`에 넣습니다.
4. (선택) Roblox 그룹 ID를 `Config.GroupId`에 넣습니다. 그룹 가입 보상과 +10% 보너스가 켜집니다.
5. (선택) 구독 상품 ID를 `Config.Subscription.Id`에 넣습니다 (예: `"EXP-..."`).
6. (선택) 보상형 광고 자격을 충족하면 `Config.Products.AdReward.Id`를 넣고 `Config.RewardedAds.Enabled = true`로 바꿉니다. 켜기 전에 [AdService 문서](https://create.roblox.com/docs/production/promotion/rewarded-video-ads)의 메서드 이름과 `MonetizationService.luau`의 `watchAd`가 일치하는지 확인하세요.
7. **Game Settings → Monetization**에서 비공개 서버를 켜고 가격을 정합니다.

> 화면에 보이는 가격은 Roblox에 등록한 실제 가격을 자동으로 읽어 옵니다. Config의 `Price`는 ID가 없을 때만 쓰는 기본값입니다.

| 게임패스 키 | 권장가 | | 개발자 상품 키 | 권장가 |
|---|---|---|---|---|
| VIP | 299 | | Gems100 / 550 / 1200 / 3500 | 39 / 179 / 349 / 899 |
| DoubleCoins | 249 | | CoinPack | 49 |
| MegaPower | 199 | | CoinBoost / LuckBoost / PowerBoost | 79 / 69 / 69 |
| AutoMine | 149 | | ServerLuck | 149 |
| AutoSell | 129 | | SummonMeteor | 99 |
| ExtraPets | 199 | | SeasonPremium / SkipTiers | 399 / 149 |
| Lucky | 179 | | StarterPack | 99 |
| TripleHatch | 149 | | GoldenEgg1 / GoldenEgg3 | 79 / 199 |
| BigBackpack | 99 | | AdReward (광고 보상) | - |
| Speed | 79 | | | |

---

## 🗂 프로젝트 구조

```
default.project.json          Rojo 프로젝트 (ReplicatedStorage / ServerScriptService / StarterPlayerScripts)
src/shared/                   → ReplicatedStorage.Shared
  Config.luau                 ★ 모든 밸런스·가격·확률·이벤트 설정 (여기만 고치면 됨)
  Util.luau                   숫자 포맷, 가중치 랜덤, 날짜/주차 계산
  PetModel.luau               파트로 펫 모델 생성 (ReplicatedStorage.PetModels에 모델을 넣으면 교체됨)
src/server/                   → ServerScriptService.Server
  Main.server.luau            서비스 초기화 순서
  Services/
    Net.luau                  리모트 + 액션별 레이트 리밋
    DataService.luau          DataStore 저장/로드, 세션 락, 자동 저장, 클라이언트 동기화
    StatsService.luau         데미지·코인·행운·용량 배수 계산, 친구/그룹/Premium 보너스
    MonetizationService.luau  게임패스, ProcessReceipt, 구독, 광고, PolicyService
    BoostService.luau         개인/서버 부스트
    WorldService.luau         맵 전체 절차적 생성
    CharacterService.luau     곡괭이 지급, 이동속도, 머리 위 랭크/칭호
    EconomyService.luau       곡괭이 업그레이드, 구역 해금, 환생, 텔레포트
    PetService.luau           알 부화, 행운, 장착, 삭제, 희귀 펫 공지
    MiningService.luau        광석 블록, 채굴 판정, PvP 약탈
    MeteorService.luau        ☄️ 운석 레이드 이벤트
    ProgressionService.luau   출석, 퀘스트, 선물, 시즌패스, 주간 랭크
    LeaderboardService.luau   글로벌 리더보드 + 주간 Top 10 보상 + 칭호
src/client/                   → StarterPlayerScripts.Client
  Main.client.luau            클라이언트 부트스트랩
  Net.luau / State.luau       통신, 상태 미러
  UI/                         Lib(UI 툴킷), Root(스케일링), Upsell, Hatch(부화 연출), Panels/*(화면 9종)
  Controllers/                HUD, Mining(입력·이펙트), PetFollow, WorldFX(게이트·채팅 태그), MeteorUI
```

## 🔐 보안 & 데이터 무결성
- 모든 재화 변경은 **서버에서만** 처리합니다. 클라이언트는 "요청"만 보냅니다.
- 채굴은 서버가 사거리(13 studs)와 쿨다운을 검증하고, PvP는 거리·구역·무적 시간을 검증합니다.
- 모든 리모트 액션에 레이트 리밋이 걸려 있고 `pcall`로 보호됩니다.
- `ProcessReceipt`는 PurchaseId를 저장해 **중복 지급을 막고**, 지급 직후 저장합니다.
- 세션 락으로 서버를 빠르게 옮겨 다니며 아이템을 복사하는 것을 막습니다.

## 🛠 자주 바꾸는 설정
| 하고 싶은 것 | 위치 |
|---|---|
| 운석 주기/보상 | `Config.Meteor` |
| 새 구역 추가 | `Config.Zones`에 항목 추가 (+ `Config.Ores`, `Config.PointsPerBlock`) |
| 새 펫/알 | `Config.Pets`, `Config.Eggs`, `Config.EggOrder` |
| 새 시즌 시작 | `Config.Season.Id`를 +1 하고 `Config.SeasonTiers` 보상 변경 |
| 랭크 기준/보상 | `Config.Ranks`, `Config.Leaderboards.WeeklyTopReward` |
| 출석/선물/퀘스트 | `Config.DailyRewards`, `Config.PlaytimeGifts`, `Config.Quests` |
| 프로모 코드 추가 | `Config.Codes` (예: `SUMMER = { Reward = { Gems = 500 }, ExpiresAt = 0 }`) |
| 미니 이벤트 주기/종류 | `Config.Events` |
| 휠 상품/쿨타임 | `Config.Spin` |
| 크리·콤보·럭키 확률 | `Config.Crit`, `Config.Combo`, `Config.LuckyOres`, `Config.PetVariants` |
| 효과음 / 배경음악 | `Config.Sounds` (Toolbox → Audio의 `rbxassetid://` 넣기), `Config.Music` |
