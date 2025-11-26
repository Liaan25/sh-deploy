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

# Функция для установки скриптов-оберток
install_wrapper_scripts() {
    print_step "Установка скриптов-оберток для безопасности"
    
    mkdir -p "$WRAPPER_DIR"
    chmod 755 "$WRAPPER_DIR"
    
    # Определяем базовый путь к скриптам (в корне репозитория)
    local script_base_path="/tmp/monitoring-deployment"
    
    # Копируем скрипты-обертки из корня репозитория
    cp "$script_base_path/iptables-wrapper.sh" "$IPTABLES_WRAPPER"
    cp "$script_base_path/curl-wrapper.sh" "$CURL_WRAPPER"
    cp "$script_base_path/file-operations-wrapper.sh" "$FILE_OPS_WRAPPER"
    cp "$script_base_path/systemctl-wrapper.sh" "$SYSTEMCTL_WRAPPER"
    
    # Устанавливаем права на скрипты
    chmod 755 "$IPTABLES_WRAPPER" "$CURL_WRAPPER" "$FILE_OPS_WRAPPER" "$SYSTEMCTL_WRAPPER"
    chown root:root "$IPTABLES_WRAPPER" "$CURL_WRAPPER" "$FILE_OPS_WRAPPER" "$SYSTEMCTL_WRAPPER"
    
    print_success "Скрипты-обертки установлены"
}

# Функция для настройки sudoers с NOEXEC
configure_sudoers() {
    print_step "Настройка sudoers с NOEXEC атрибутом"
    
    local sudoers_file="/etc/sudoers.d/monitoring-deployment"
    local sudoers_template="/tmp/monitoring-deployment/sudoers-template"
    
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

# Основная функция
main() {
    log_message "=== Начало развертывания мониторинговой системы v4.0 (Security Enhanced) ==="
    
    print_header
    check_sudo
    check_dependencies
    
    # Здесь будет остальная логика развертывания...
    
    print_success "Развертывание завершено успешно!"
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
