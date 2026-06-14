#!/bin/bash

# Music Assistant + Home Assistant NAS 배포 스크립트
# 공식 GHCR 이미지(ghcr.io/music-assistant/server, ghcr.io/home-assistant/home-assistant)를
# pull 하여 배포한다. 이 스크립트는 NAS에서 실행된다.

set -e

# Synology: ContainerManager docker 는 /usr/local/bin 에 있는데 sudo PATH 에 없어
# 명령을 못 찾는 경우가 있다. PATH 를 보강해 항상 docker 를 찾도록 한다.
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# 색상 코드
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# 스크립트 디렉토리로 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="docker-compose.yml"

# docker compose(v2) / docker-compose(v1) 자동 감지
if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    echo -e "${RED}❌ docker compose 를 찾을 수 없습니다.${NC}"
    exit 1
fi

# 헬퍼 함수
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }

# .env 존재 확인
check_env() {
    if [ ! -f .env ]; then
        print_error ".env 파일이 없습니다. '.env.example' 을 복사해 만드세요:"
        echo "  cp .env.example .env && vi .env"
        exit 1
    fi
}

# .env 의 DATA_DIR 값 읽기 (기본: 스크립트 폴더)
get_data_dir() {
    local d
    d="$(grep -E '^DATA_DIR=' .env 2>/dev/null | cut -d= -f2-)"
    echo "${d:-$SCRIPT_DIR}"
}

# bind mount 대상 디렉토리 미리 생성
# (Synology docker 는 일반 docker 와 달리 없는 호스트 경로를 자동 생성하지 않음)
ensure_dirs() {
    local data_dir; data_dir="$(get_data_dir)"
    mkdir -p "${data_dir}/music-assistant/data" "${data_dir}/homeassistant/config"
}

# 이미지 풀
pull_images() {
    print_header "📥 GHCR 공식 이미지 풀"
    $DC -f ${COMPOSE_FILE} pull
    print_success "이미지 풀 완료!"
}

# 배포
deploy() {
    print_header "🚀 Music Assistant 배포"
    check_env
    ensure_dirs
    echo -e "${YELLOW}컨테이너 시작 중...${NC}"
    $DC -f ${COMPOSE_FILE} up -d --remove-orphans
    print_success "배포 완료!"
    echo ""
    status
}

# 업데이트 (풀 + 배포)
update() {
    print_header "🔄 Music Assistant 업데이트"
    check_env
    pull_images
    echo ""
    deploy
}

# 시작
start() {
    print_header "▶️  Music Assistant 시작"
    check_env
    ensure_dirs
    $DC -f ${COMPOSE_FILE} up -d
    print_success "시작 완료!"
    status
}

# 중지
stop() {
    print_header "⏹️  Music Assistant 중지"
    $DC -f ${COMPOSE_FILE} stop
    print_success "중지 완료!"
}

# 재시작
restart() {
    print_header "🔄 Music Assistant 재시작"
    $DC -f ${COMPOSE_FILE} restart
    print_success "재시작 완료!"
    status
}

# 상태
status() {
    print_header "📊 서비스 상태"
    $DC -f ${COMPOSE_FILE} ps
    echo ""
    local ip
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo -e "${BLUE}🌐 접속 URL:${NC}"
    echo "  Music Assistant: http://${ip:-<NAS_IP>}:8095"
    echo "  Home Assistant : http://${ip:-<NAS_IP>}:8123"
}

# 로그
logs() {
    local service=$1
    if [ -z "$service" ]; then
        print_header "📝 전체 로그"
        $DC -f ${COMPOSE_FILE} logs -f --tail=100
    else
        print_header "📝 $service 로그"
        $DC -f ${COMPOSE_FILE} logs -f --tail=100 "$service"
    fi
}

# 백업 (MA data + HA config)
backup() {
    print_header "💾 설정 백업"
    # .env 의 DATA_DIR 을 읽어 백업 대상 결정
    local data_dir; data_dir="$(get_data_dir)"

    mkdir -p backups
    local backup_file="backups/ma_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    local targets=()
    [ -d "${data_dir}/music-assistant" ] && targets+=("${data_dir}/music-assistant")
    [ -d "${data_dir}/homeassistant" ] && targets+=("${data_dir}/homeassistant")

    if [ ${#targets[@]} -eq 0 ]; then
        print_warning "백업할 데이터가 없습니다. (${data_dir})"
        return
    fi

    tar -czf "$backup_file" "${targets[@]}"
    print_success "백업 완료: $backup_file"

    # 30일 이상 된 백업 삭제
    find backups/ -name "ma_backup_*.tar.gz" -mtime +30 -delete 2>/dev/null || true
}

# 정리
clean() {
    print_header "🧹 Docker 정리"
    echo -e "${YELLOW}사용하지 않는 이미지 삭제 중...${NC}"
    docker image prune -f
    print_success "정리 완료!"
}

# 도움말
show_help() {
    echo -e "${GREEN}Music Assistant + Home Assistant NAS 배포 스크립트${NC}"
    echo ""
    echo -e "${YELLOW}사용법:${NC}  $0 <명령어> [옵션]"
    echo ""
    echo -e "${BLUE}=== 배포 ===${NC}"
    echo -e "  ${GREEN}pull${NC}             GHCR에서 최신 공식 이미지 풀"
    echo -e "  ${GREEN}deploy${NC}           컨테이너 배포"
    echo -e "  ${GREEN}update${NC}           풀 + 배포 (추천)"
    echo ""
    echo -e "${BLUE}=== 관리 ===${NC}"
    echo -e "  ${GREEN}start${NC}            서비스 시작"
    echo -e "  ${GREEN}stop${NC}             서비스 중지"
    echo -e "  ${GREEN}restart${NC}          서비스 재시작"
    echo -e "  ${GREEN}status${NC}           서비스 상태"
    echo -e "  ${GREEN}logs${NC} [service]   로그 확인 (service: music-assistant-server | homeassistant)"
    echo ""
    echo -e "${BLUE}=== 유지보수 ===${NC}"
    echo -e "  ${GREEN}backup${NC}           설정(MA data + HA config) 백업"
    echo -e "  ${GREEN}clean${NC}            사용하지 않는 Docker 이미지 정리"
    echo ""
    echo -e "${YELLOW}예시:${NC}"
    echo "  $0 update                   # 최신 이미지로 업데이트 (추천)"
    echo "  $0 logs music-assistant-server"
}

# 메인 로직
case "${1:-help}" in
    pull)    pull_images ;;
    deploy)  deploy ;;
    update)  update ;;
    start)   start ;;
    stop)    stop ;;
    restart) restart ;;
    status)  status ;;
    logs)    logs "$2" ;;
    backup)  backup ;;
    clean)   clean ;;
    help|--help|-h) show_help ;;
    *)
        print_error "알 수 없는 명령어: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
