# ☄️ Meteor Miners

광석을 캐고, 펫을 뽑고, **7분마다 떨어지는 운석을 서버 전체가 쟁탈**하며 **매주 리셋되는 랭크**에서 경쟁하는 로블록스 채굴 시뮬레이터입니다.

- 📈 [01. 로블록스 인기 게임 & 수익화 분석](docs/01_시장분석.md)
- 🎮 [02. 게임 기획서 (코어 루프, 경쟁, 수익화, 밸런스, 로드맵)](docs/02_게임기획서.md)

맵, 펫, UI까지 **모두 코드로 생성**되므로 3D 에셋 없이 바로 플레이할 수 있습니다.

---

## 🚀 빠른 시작

### 방법 A: 플레이스 파일 바로 열기 (가장 쉬움)
1. [Rojo](https://rojo.space)로 플레이스 파일을 빌드합니다.
   ```bash
   rojo build default.project.json -o MeteorMiners.rbxlx
   ```
2. Roblox Studio에서 `MeteorMiners.rbxlx`를 엽니다.
3. **Play** (F5)를 누르면 끝입니다.

### 방법 B: Rojo 실시간 동기화 (개발용)
1. Studio에 Rojo 플러그인을 설치합니다.
2. 터미널에서 `rojo serve`를 실행합니다.
3. Studio의 Rojo 플러그인에서 **Connect**를 누릅니다.
4. Workspace의 `StreamingEnabled`를 **꺼 주세요** (클라이언트가 게이트와 광석을 직접 참조합니다).
5. 기본 템플릿(Baseplate)에서 시작했다면 기본 `Baseplate`와 `SpawnLocation`은 삭제하세요. 맵은 서버가 시작할 때 자동으로 생성됩니다.

### Studio 테스트 팁
- **Game Settings → Security → Enable Studio Access to API Services**를 켜면 DataStore 저장과 리더보드가 동작합니다. 꺼져 있어도 임시 데이터로 플레이할 수 있습니다.
- 상품 ID가 `0`인 상태에서는 **Studio에서 구매가 즉시 시뮬레이션됩니다** (`[TEST]` 표시). 모든 결제 흐름을 실제 상품을 만들기 전에 테스트할 수 있습니다.
- 화면 왼쪽 아래 **🛠 DEV** 버튼(Studio에서만 보임)으로 코인·젬·랭크 점수·시즌 XP를 지급하고, 운석을 즉시 소환하고, 가방을 채우고, 데이터를 초기화할 수 있습니다. 라이브 서버에서는 서버가 차단합니다.
- 운석이 빨리 보고 싶다면 DEV → Meteor를 누르거나 `Config.Meteor.IntervalSeconds`를 줄이세요. 서버 시작 후 첫 운석은 최대 150초 뒤에 떨어집니다.
- 설정 검증: [Lune](https://lune-org.github.io/docs)을 설치한 뒤 `lune run tests/ConfigCheck.luau`를 실행하면 펫·광석·상품 이름 오타와 확률 합계를 검사합니다.
- 멀티플레이 테스트 (PvP, 운석 경쟁): **Test → Clients and Servers → 2~3 Players → Start**

---

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
    EconomyService.luau       판매, 업그레이드, 구역 해금, 환생, 텔레포트
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
