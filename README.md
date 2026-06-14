# Music Assistant on Synology NAS

Synology NAS에서 **Music Assistant(MA)** + **Home Assistant(HA)** 를 Docker로 구축하는 가이드입니다.

- **Music Assistant**: 음악 라이브러리 관리 + 멀티룸 스트리밍 서버
- **Home Assistant**: (선택) 자동화·대시보드에서 음악 제어

---

## 1. 사전 준비

### 1-1. Synology 패키지 설치
DSM → **패키지 센터** 에서 설치:
- **Container Manager** (구 Docker)

### 1-2. SSH 활성화
> ⚠️ **중요**: Music Assistant는 `cap_add` / `apparmor:unconfined` / `network_mode: host` 같은
> 고급 옵션이 필요합니다. Synology Container Manager **GUI로는 이 옵션들을 줄 수 없으므로**,
> 반드시 **SSH + docker compose** 방식으로 설치해야 합니다.

DSM → **제어판 → 터미널 및 SNMP → SSH 서비스 활성화** 체크.

### 1-3. 음악 폴더 준비
DSM **File Station**에서 음악 파일을 모아둘 공유 폴더를 만듭니다 (예: `music`).
실제 경로는 보통 `/volume1/music` 입니다.

---

## 2. 네트워크 요구사항 (가장 중요)

Music Assistant는 Chromecast, Sonos, AirPlay 등 플레이어를 **mDNS/UPnP**로 자동 검색합니다.
이를 위해 `network_mode: host` (Layer 2 직접 접근)가 **필수**입니다.

➡️ **NAS, 스피커, (사용 시) Home Assistant가 모두 같은 서브넷(같은 공유기 LAN)에 있어야 합니다.**
VLAN으로 분리되어 있으면 기기 검색이 안 됩니다.

사용 포트:
| 서비스 | 포트 | 용도 |
|--------|------|------|
| Music Assistant | `8095` | Web UI |
| Music Assistant | `8097` | 오디오 스트리밍 |
| Home Assistant | `8123` | Web UI |

DSM 자체 포트(5000/5001)와 충돌하지 않습니다.

---

## 3. 설치

SSH로 NAS에 접속한 뒤:

```bash
# 1) 운영 폴더로 이동 (이미 파일이 여기 있음)
cd /volume1/code_work/music_assist

# 2) 환경설정 파일 생성 후 본인 경로에 맞게 수정
cp .env.example .env
vi .env        # MUSIC_DIR(음악 폴더 경로) 확인/수정

# 3) 컨테이너 실행
sudo docker compose up -d

# 4) 로그 확인
sudo docker compose logs -f music-assistant-server
```

> Home Assistant가 필요 없으면, `docker-compose.yml`에서 `homeassistant:` 블록을 지우거나
> `sudo docker compose up -d music-assistant-server` 로 MA만 실행하세요.

---

## 4. 초기 설정

### 4-1. Music Assistant 접속
브라우저에서 `http://<NAS_IP>:8095` 접속 → 초기 설정 마법사 진행.

### 4-2. 음악 소스(Provider) 추가
MA 설정 → **Settings → Music Providers → + Add**

| 소스 | 추가 방법 |
|------|-----------|
| **NAS 로컬 파일** | `Filesystem` 프로바이더 → 경로 `/media/music` 입력 (compose에서 마운트한 경로) |
| **Spotify** | `Spotify` 프로바이더 → Premium 계정 로그인 |
| **YouTube Music** | `YouTube Music` 프로바이더 → 계정 인증 |
| **Tidal / Qobuz** | 각 프로바이더 선택 → 계정 로그인 |
| **내 라디오 서비스** | 아래 7번 항목 참고 |

### 4-3. 출력 장치(Player) 추가

> MA에서 플레이어는 **"플레이어 프로바이더(Player Provider)를 추가"** 하면 동작합니다.
> 프로바이더를 켜면 해당 프로토콜을 쓰는 기기가 **계속 자동 검색**됩니다.
> (검색이 되는 이유 = compose의 `network_mode: host` + 멀티캐스트/UPnP 접근. 그래서 Docker 추가 설정 불필요)

MA 설정 → **Settings → Providers → + Add a new provider** 에서 아래를 필요에 따라 추가:

| 프로바이더 | 대상 기기 | 비고 |
|-----------|-----------|------|
| **Google Cast** | Chromecast / Google Nest | 자동 검색 |
| **Sonos** | Sonos 스피커 | 자동 검색 |
| **AirPlay** | HomePod, Apple TV, AirPlay 스피커 | 자동 검색 |
| **DLNA** | DLNA/UPnP 범용 스피커·리시버·TV | 자동 검색 (아래 5번 참고) |
| **WiiM** | WiiM Mini/Pro/Amp 등 (LinkPlay) | 전용 프로바이더 (아래 6번 참고) |
| **Bluesound** | Bluesound / BluOS 기기 | 자동 검색 |
| **Squeezelite** | Squeezebox 호환 기기 | 자동 검색 |
| **Snapcast** | 여러 방 완벽 동기화 | 추가 설정 필요 |

- **내장 웹 플레이어**: 별도 추가 없이 MA UI 상단에서 현재 브라우저를 스피커로 사용 가능.

---

## 5. DLNA / UPnP 스피커 연동

DLNA는 TV·AV리시버·범용 네트워크 스피커가 널리 쓰는 표준입니다.

1. MA 설정 → **Settings → Providers → + Add → DLNA** 추가.
2. 활성화하면 같은 LAN의 DLNA/UPnP 기기가 **자동으로 Players 목록에 나타납니다.**
3. 안 나오면:
   - 기기와 NAS가 **같은 서브넷**인지 확인 (VLAN 분리 금지).
   - 공유기에서 **IGMP Snooping / 멀티캐스트**가 켜져 있는지 확인 (UPnP 검색에 필요).
   - 그래도 안 되면 기기 IP를 고정한 뒤 MA에서 잠시 기다리면 재검색됩니다.

> ⚠️ DLNA는 제조사마다 표준 구현 품질이 들쭉날쭉합니다.
> 같은 기기가 **AirPlay·Squeezelite·WiiM 같은 다른 프로토콜도 지원한다면 그쪽을 우선** 쓰는 것이 안정적입니다.

---

## 6. WiiM 연동

WiiM(Mini/Pro/Pro Plus/Amp 등)은 LinkPlay 기반이며 MA에 **전용 WiiM 프로바이더**가 있습니다.

1. **WiiM Home 앱**에서 기기를 먼저 Wi-Fi에 연결해 두세요 (최초 1회).
   - 가능하면 WiiM을 **유선 LAN 또는 NAS와 같은 무선 대역(2.4/5GHz 동일 SSID)** 에 둡니다.
2. MA 설정 → **Settings → Providers → + Add → WiiM** 추가.
3. 활성화하면 WiiM 기기가 자동 검색되어 Players에 나타납니다.

> WiiM은 AirPlay·DLNA·Squeezelite로도 잡히지만, **전용 WiiM 프로바이더가 가장 기능이 완전**합니다
> (볼륨/그룹/메타데이터). 중복 등록을 피하려면 WiiM 프로바이더 하나만 쓰는 것을 권장합니다.

---

## 7. "내가 운영하는 라디오 서비스" 연결

직접 운영하는 라디오는 **스트림 URL** 한 줄로 추가합니다.

MA 설정 → **Settings → Music Providers → + Add → Radio Browser** 설치 후,
또는 라이브러리에서 **Radio → Add custom radio station** 으로:
- **Name**: 라디오 이름
- **Stream URL**: 본인 라디오 스트림 주소 (예: `https://radio.example.com/stream.mp3` 또는 `.../stream.aac`, HLS `.m3u8`)

> 지원 포맷: MP3 / AAC / OGG / FLAC 직접 스트림, HLS(`.m3u8`), Icecast/Shoutcast.
> 본인 라디오 서버의 스트림 엔드포인트 URL만 알면 됩니다.

---

## 8. Home Assistant 연동 (선택)

1. `http://<NAS_IP>:8123` 접속 → HA 계정 생성.
2. HA → **설정 → 기기 및 서비스 → 통합구성요소 추가 → "Music Assistant"** 검색.
3. 서버 주소 `http://<NAS_IP>:8095` 입력 → 연결.
4. 이제 HA 대시보드/자동화에서 MA 플레이어를 미디어 플레이어로 제어할 수 있습니다.
   (예: "아침 7시에 거실 스피커로 내 라디오 재생")

---

## 9. 운영 / 유지보수 (`deploy.sh`)

NAS에서는 `deploy.sh` 로 관리합니다 (다른 프로젝트와 동일한 워크플로우).

```bash
cd /volume1/code_work/music_assist

sudo ./deploy.sh update     # GHCR 최신 이미지 풀 + 배포 (추천)
sudo ./deploy.sh status     # 상태 + 접속 URL
sudo ./deploy.sh logs music-assistant-server   # 로그
sudo ./deploy.sh restart    # 재시작
sudo ./deploy.sh stop       # 중지
sudo ./deploy.sh backup     # 설정 백업 (MA data + HA config)
sudo ./deploy.sh clean      # 미사용 이미지 정리
sudo ./deploy.sh help       # 전체 명령어
```

> Music Assistant/Home Assistant는 **공식 이미지를 그대로 사용**하므로 자체 GHCR 빌드/푸시가 없습니다.
> `deploy.sh update` 가 공식 이미지를 GHCR에서 pull 해 최신화합니다.
> 설정 파일(compose/deploy/README)은 git으로 버전 관리합니다 (아래 11번).

**백업**: `sudo ./deploy.sh backup` 또는 `DATA_DIR` 아래
`music-assistant/`, `homeassistant/` 폴더를 백업하면 설정·계정 연동이 모두 보존됩니다.
Synology **Hyper Backup** 정기 백업도 권장.

---

## 10. 문제 해결

| 증상 | 원인 / 해결 |
|------|-------------|
| 플레이어가 검색 안 됨 | NAS와 스피커가 다른 서브넷/VLAN. 같은 LAN으로 통일. `network_mode: host` 확인 |
| 컨테이너 실행 실패 (`apparmor`) | Synology에서 apparmor 미지원 시 해당 줄 제거 후 재시도 |
| 음악 폴더 안 보임 | `.env`의 `MUSIC_DIR` 경로 오타 / 권한. 컨테이너 안 경로는 `/media/music` |
| 권한 오류 | `sudo` 로 실행했는지 확인 |
| 라디오 재생 안 됨 | 스트림 URL을 브라우저에서 직접 열어 재생되는지 먼저 확인 |

---

## 11. 코드 관리 / 배포 워크플로우

설정은 GitHub(`HyunjoonKwak/music_assistant`)에서 버전 관리합니다.

**로컬(Mac)에서 설정 변경 시:**
```bash
cd /Users/specialrisk_mac/code_work/music_assist
git add -A && git commit -m "chore: update config"
git push
```

**NAS에 반영:**
```bash
cd /volume1/code_work/music_assist
git pull              # 변경된 compose/deploy 동기화
sudo ./deploy.sh update
```

> 최초 1회 NAS에 클론:
> `git clone git@github.com:HyunjoonKwak/music_assistant.git /volume1/code_work/music_assist`
> (또는 기존 폴더에서 `git init && git remote add origin ... && git pull`)
> 그다음 `cp .env.example .env` 로 `.env` 를 만들고 경로를 채웁니다. `.env` 는 git에 올라가지 않습니다.

---

## 파일 구성

```
music_assist/
├── docker-compose.yml   # MA + HA 컨테이너 정의 (공식 이미지)
├── deploy.sh            # NAS 배포/운영 스크립트 (update/status/logs/backup ...)
├── .env.example         # 환경설정 템플릿 → 복사해서 .env 로 사용
├── .gitignore           # .env, 런타임 데이터 제외
└── README.md            # 이 문서
```
