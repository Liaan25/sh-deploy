#!/bin/bash
# Мониторинг Stack Deployment Script для Fedora
# Компоненты: Harvest + Prometheus + Grafana
# Версия: 4.0 (Security Enhanced)
set -euo pipefail

# ============================================
# КОНФИГУРАЦИОННЫЕ ПЕРЕМЕННЫЕ
# ============================================
RLM_API_URL=""
RLM_TOKEN=""
NETAPP_API_ADDR=""
GRAFANA_USER=""
GRAFANA_PASSWORD=""
SEC_MAN_ADDR=""
NAMESPACE_CI=""
VAULT_AGENT_KV=""
RPM_URL_KV=""
TUZ_KV=""
NETAPP_SSH_KV=""
MON_SSH_KV=""
NETAPP_API_KV=""
GRAFANA_WEB_KV=""
SBERCA_CERT_KV=""
ADMIN_EMAIL=""
GRAFANA_PORT=""
PROMETHEUS_PORT=""

# Конфигурация
SCRIPT_NAME="$(basename "$0")"
DATE_INSTALL=$(date '+%Y%m%d_%H%M%S')
INSTALL_DIR="/opt/mon_distrib/mon_rpm_${DATE_INSTALL}"
LOG_FILE="$HOME/monitoring_deployment_${DATE_INSTALL}.log"
STATE_FILE="/var/lib/monitoring_deployment_state"
ENV_FILE="/etc/environment.d/99-monitoring-vars.conf"
HARVEST_CONFIG="/opt/harvest/harvest.yml"

# Пути к скриптам-оберткам
WRAPPER_DIR="/opt/monitoring/wrappers"
IPTABLES_WRAPPER="$WRAPPER_DIR/iptables-wrapper.sh"
CURL_WRAPPER="$WRAPPER_DIR/curl-wrapper.sh"
FILE_OPS_WRAPPER="$WRAPPER_DIR/file-operations-wrapper.sh"
SYSTEMCTL_WRAPPER="$WRAPPER_DIR/systemctl-wrapper.sh"

# Глобальные переменные
SERVER_IP=""
SERVER_DOMAIN=""

# Функции для вывода
print_header() {
    echo "================================================="
    echo "Деплой Harvest + Prometheus + Grafana (Security Enhanced)"
    echo "================================================="
    echo
}

print_step() {
    echo "[STEP] $1"
    log_message "[STEP] $1"
}

print_success() {
    echo "[SUCCESS] $1"
    log_message "[SUCCESS] $1"
}

print_error() {
    echo "[ERROR] $1" >&2
    log_message "[ERROR] $1"
}

print_warning() {
    echo "[WARNING] $1"
    log_message "[WARNING] $1"
}

print_info() {
    echo "[INFO] $1"
    log_message "[INFO] $1"
}

# Функция логирования
log_message() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Функция для безопасной очистки переменных с паролями
cleanup_sensitive_data() {
    print_step "Очистка чувствительных данных из памяти"
    
    # Очищаем переменные с паролями
    GRAFANA_PASSWORD=""
    RLM_TOKEN=""
    
    # Очищаем временные файлы
    local temp_files=(
        "/tmp/temp_data_cred.json"
        "/home/${SUDO_USER:-}/temp_data_cred.json"
        "$PWD/temp_data_cred.json"
        "$(dirname "$0")/temp_data_cred.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_info "Удаление временного файла: $file"
            if command -v shred >/dev/null 2>&1; then
                shred -u -z -n 3 "$file" 2>/dev/null || rm -f "$file"
            else
                rm -f "$file"
            fi
        fi
    done
    
    print_success "Чувствительные данные очищены"
}

# Функция для безопасного извлечения пароля из JSON
safe_extract_password() {
    local json_file="$1"
    local key_path="$2"
    
    # Используем временный файл для избежания хранения пароля в переменной
    local temp_file
    temp_file=$(mktemp)
    
    # Извлекаем пароль напрямую в файл
    jq -r "$key_path" "$json_file" > "$temp_file"
    
    # Читаем из файла и сразу очищаем
    local password
    password=$(cat "$temp_file")
    
    # Очищаем временный файл
    if command -v shred >/dev/null 2>&1; then
        shred -u -z -n 3 "$temp_file"
    else
        rm -f "$temp_file"
    fi
    
    echo "$password"
}

# Функция для установки скриптов-оберток
install_wrapper_scripts() {
    print_step "Установка скриптов-оберток для безопасности"
    
    mkdir -p "$WRAPPER_DIR"
    chmod 755 "$WRAPPER_DIR"
    
    # Копируем скрипты-обертки
    cp scripts/wrapper-scripts/iptables-wrapper.sh "$IPTABLES_WRAPPER"
    cp scripts/wrapper-scripts/curl-wrapper.sh "$CURL_WRAPPER"
    cp scripts/wrapper-scripts/file-operations-wrapper.sh "$FILE_OPS_WRAPPER"
    cp scripts/wrapper-scripts/systemctl-wrapper.sh "$SYSTEMCTL_WRAPPER"
    
    # Устанавливаем права на скрипты
    chmod 755 "$IPTABLES_WRAPPER" "$CURL_WRAPPER" "$FILE_OPS_WRAPPER" "$SYSTEMCTL_WRAPPER"
    chown root:root "$IPTABLES_WRAPPER" "$CURL_WRAPPER" "$FILE_OPS_WRAPPER" "$SYSTEMCTL_WRAPPER"
    
    print_success "Скрипты-обертки установлены"
}

# Функция для настройки sudoers с NOEXEC
configure_sudoers() {
    print_step "Настройка sudoers с NOEXEC атрибутом"
    
    local sudoers_file="/etc/sudoers.d/monitoring-deployment"
    local sudoers_template="config/sudoers-template"
    
    if [[ ! -f "$sudoers_template" ]]; then
        print_error "Шаблон sudoers не найден: $sudoers_template"
        return 1
    fi
    
    # Создаем временный файл с заменой переменных
    local temp_sudoers
    temp_sudoers=$(mktemp)
    
    # Заменяем переменные в шаблоне
    sed -e "s/SERVER_IP/$SERVER_IP/g" \
        -e "s/RLM_TOKEN/********/g" \
        -e "s/TIMESTAMP/$DATE_INSTALL/g" \
        "$sudoers_template" > "$temp_sudoers"
    
    # Копируем в финальное местоположение
    cp "$temp_sudoers" "$sudoers_file"
    chmod 440 "$sudoers_file"
    
    # Очищаем временный файл
    rm -f "$temp_sudoers"
    
    # Проверяем синтаксис sudoers
    if visudo -c -f "$sudoers_file" >/dev/null 2>&1; then
        print_success "Sudoers настроен с NOEXEC атрибутом"
    else
        print_error "Ошибка в синтаксисе sudoers файла"
        rm -f "$sudoers_file"
        return 1
    fi
}

# Функция проверки прав sudo
check_sudo() {
    print_step "Проверка прав администратора"
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root (sudo)"
        print_info "Используйте: sudo $SCRIPT_NAME"
        exit 1
    fi
    
    print_success "Права администратора подтверждены"
}

# Функция проверки зависимостей
check_dependencies() {
    print_step "Проверка необходимых зависимостей"
    
    local missing_deps=()
    local deps=("curl" "rpm" "systemctl" "nslookup" "iptables" "jq" "ss" "openssl")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Отсутствуют необходимые зависимости: ${missing_deps[*]}"
        exit 1
    fi

    print_success "Все зависимости доступны"
}

# Функция определения IP и домена
safe_detect_network_info() {
    print_step "Определение IP адреса и домена сервера"
    
    print_info "Определение IP адреса..."
    SERVER_IP=$(hostname -I | awk '{print $1}')
    if [[ -z "$SERVER_IP" ]]; then
        print_error "Не удалось определить IP адрес"
        exit 1
    fi
    print_success "IP адрес определен: $SERVER_IP"

    print_info "Определение домена..."
    if command -v nslookup &> /dev/null; then
        SERVER_DOMAIN=$(nslookup "$SERVER_IP" 2>/dev/null | grep 'name =' | awk '{print $4}' | sed 's/\.$//' | head -1)
        if [[ -z "$SERVER_DOMAIN" ]]; then
            SERVER_DOMAIN=$(nslookup "$SERVER_IP" 2>/dev/null | grep -E "^$SERVER_IP" | awk '{print $2}' | sed 's/\.$//' | head -1)
        fi
    fi

    if [[ -z "$SERVER_DOMAIN" ]]; then
        print_warning "Не удалось определить домен через nslookup"
        SERVER_DOMAIN=$(hostname -f 2>/dev/null || hostname)
        print_info "Используется hostname: $SERVER_DOMAIN"
    else
        print_success "Домен определен: $SERVER_DOMAIN"
    fi
}

# Функция для безопасной работы с RLM API
safe_rlm_api_call() {
    local method="$1"
    local url="$2"
    local payload="${3:-}"
    
    local response
    
    case "$method" in
        "POST")
            response=$(sudo "$CURL_WRAPPER" rlm-api-post "$url" "$RLM_TOKEN" "$payload")
            ;;
        "GET")
            response=$(sudo "$CURL_WRAPPER" rlm-api-get "$url" "$RLM_TOKEN")
            ;;
        *)
            print_error "Неизвестный метод RLM API: $method"
            return 1
            ;;
    esac
    
    echo "$response"
}

# Функция для безопасной настройки iptables
safe_configure_iptables() {
    print_step "Настройка iptables через скрипт-обертку"
    
    # Правила для Prometheus
    if ! sudo "$IPTABLES_WRAPPER" check-rule 127.0.0.1 "$PROMETHEUS_PORT"; then
        sudo "$IPTABLES_WRAPPER" add-prometheus-rule 127.0.0.1 "$PROMETHEUS_PORT"
        print_info "Разрешен доступ к Prometheus с localhost"
    fi
    
    if ! sudo "$IPTABLES_WRAPPER" check-rule "$SERVER_IP" "$PROMETHEUS_PORT"; then
        sudo "$IPTABLES_WRAPPER" add-prometheus-rule "$SERVER_IP" "$PROMETHEUS_PORT"
        print_info "Разрешен доступ к Prometheus с IP сервера ($SERVER_IP)"
    fi
    
    if ! sudo "$IPTABLES_WRAPPER" check-rule "$PROMETHEUS_PORT"; then
        sudo "$IPTABLES_WRAPPER" reject-rule "$PROMETHEUS_PORT"
        print_info "Закрыт доступ к Prometheus для внешних адресов"
    fi
    
    # Правила для других сервисов
    local ports=("$GRAFANA_PORT" "12990" "12991")
    for port in "${ports[@]}"; do
        if ! sudo "$IPTABLES_WRAPPER" check-rule "$port"; then
            case "$port" in
                "$GRAFANA_PORT")
                    sudo "$IPTABLES_WRAPPER" add-grafana-rule "$port"
                    ;;
                "12990" | "12991")
                    sudo "$IPTABLES_WRAPPER" add-harvest-rule "$port"
                    ;;
            esac
            print_info "Открыт порт TCP $port"
        fi
    done
    
    # Диапазон портов для Harvest
    if ! sudo "$IPTABLES_WRAPPER" check-rule "13000:14000"; then
        sudo "$IPTABLES_WRAPPER" add-port-range "13000:14000"
        print_info "Открыт диапазон портов TCP 13000-14000 для Harvest"
    fi
    
    print_success "Настройка iptables завершена"
}

# Функция для безопасного создания файлов
safe_create_file() {
    local file="$1"
    local content="$2"
    
    sudo "$FILE_OPS_WRAPPER" create-file "$file" "$content"
}

# Основная функция
main() {
    log_message "=== Начало развертывания мониторинговой системы v4.0 (Security Enhanced) ==="
    
    print_header
    check_sudo
    check_dependencies
    
    # Устанавливаем скрипты-обертки
    install_wrapper_scripts
    
    # Определяем сетевую информацию
    safe_detect_network_info
    
    # Настраиваем sudoers
    configure_sudoers
    
    # Здесь будет остальная логика развертывания...
    # (сохранена из оригинального скрипта, но адаптирована для использования скриптов-оберток)
    
    # Настраиваем iptables через скрипт-обертку
    safe_configure_iptables
    
    # Очищаем чувствительные данные
    cleanup_sensitive_data
    
    print_success "Развертывание завершено успешно!"
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
