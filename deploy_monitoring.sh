#!/bin/bash
# Мониторинг Stack Deployment Script для Fedora
# Компоненты: Harvest + Prometheus + Grafana
# Версия: 4.0 (Security Enhanced - Full Deployment)
set -euo pipefail

# ============================================
# КОНФИГУРАЦИОННЫЕ ПЕРЕМЕННЫЕ
# ============================================
RLM_API_URL=""
RLM_TOKEN=""
NETAPP_API_ADDR=""
GRAFANA_USER=""
GRAFANA_PASSWORD=""
SEC_MAN_ROLE_ID=""
SEC_MAN_SECRET_ID=""
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
NETAPP_POLLER_NAME=""

# Конфигурация
SEC_MAN_ADDR="${SEC_MAN_ADDR^^}"
SCRIPT_NAME="$(basename "$0")"
DATE_INSTALL=$(date '+%Y%m%d_%H%M%S')
INSTALL_DIR="/opt/mon_distrib/mon_rpm_${DATE_INSTALL}"
LOG_FILE="$HOME/monitoring_deployment_${DATE_INSTALL}.log"
STATE_FILE="/var/lib/monitoring_deployment_state"
ENV_FILE="/etc/environment.d/99-monitoring-vars.conf"
HARVEST_CONFIG="/opt/harvest/harvest.yml"
VAULT_CONF_DIR="/opt/vault/conf"
VAULT_LOG_DIR="/opt/vault/log"
VAULT_CERTS_DIR="/opt/vault/certs"
VAULT_AGENT_HCL="${VAULT_CONF_DIR}/agent.hcl"
VAULT_ROLE_ID_FILE="${VAULT_CONF_DIR}/role_id.txt"
VAULT_SECRET_ID_FILE="${VAULT_CONF_DIR}/secret_id.txt"
VAULT_DATA_CRED_JS="${VAULT_CONF_DIR}/data_cred.js"
LOCAL_CRED_JSON="/tmp/temp_data_cred.json"

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
    echo "Деплой Harvest + Prometheus + Grafana (Security Enhanced - Full)"
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
    SEC_MAN_SECRET_ID=""
    
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

# Функция для безопасного определения сетевой информации
safe_detect_network_info() {
    print_step "Определение сетевой информации сервера"
    
    # Безопасно определяем IP сервера
    if command -v hostname >/dev/null 2>&1; then
        SERVER_DOMAIN=$(hostname -f 2>/dev/null || hostname 2>/dev/null)
    else
        SERVER_DOMAIN=$(cat /etc/hostname 2>/dev/null || echo "unknown")
    fi
    
    # Безопасно определяем IP адрес
    if command -v ip >/dev/null 2>&1; then
        SERVER_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' 2>/dev/null || echo "")
    elif command -v hostname >/dev/null 2>&1; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' 2>/dev/null || echo "")
    else
        SERVER_IP=""
    fi
    
    # Если IP не определен, используем localhost
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP="127.0.0.1"
        print_warning "Не удалось определить внешний IP сервера, используется localhost"
    fi
    
    print_info "Домен сервера: $SERVER_DOMAIN"
    print_info "IP сервера: $SERVER_IP"
    
    print_success "Сетевая информация определена"
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

# Функция для проверки и установки рабочей директории
ensure_working_directory() {
    local target_dir="/tmp"
    if ! pwd >/dev/null 2>&1; then
        print_warning "Текущая директория недоступна, переключаемся на $target_dir"
        cd "$target_dir" || {
            print_error "Не удалось переключиться на $target_dir"
            exit 1
        }
    fi
    local current_dir
    current_dir=$(pwd)
    print_info "Текущая рабочая директория: $current_dir"
}

# Функция для установки скриптов-оберток
install_wrapper_scripts() {
    print_step "Установка скриптов-оберток для безопасности"
    
    mkdir -p "$WRAPPER_DIR"
    chmod 755 "$WRAPPER_DIR"
    
    # Определяем базовый путь к скриптам (относительно текущего скрипта)
    local script_dir
    script_dir=$(dirname "$(realpath "$0")")
    local script_base_path="$script_dir/scripts/wrapper-scripts"
    
    # Проверяем существование скриптов
    if [[ ! -f "$script_base_path/iptables-wrapper.sh" ]]; then
        print_error "Скрипт iptables-wrapper.sh не найден по пути: $script_base_path"
        return 1
    fi
    
    # Копируем скрипты-обертки в системную директорию
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
    print_step "Подготовка шаблона sudoers для службы безопасности"
    
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
    
    # Сохраняем подготовленный шаблон для службы безопасности
    local security_sudoers="/tmp/monitoring-deployment-sudoers-prepared"
    cp "$temp_sudoers" "$security_sudoers"
    chmod 644 "$security_sudoers"
    
    # Очищаем временный файл
    rm -f "$temp_sudoers"
    
    print_success "Шаблон sudoers подготовлен для службы безопасности: $security_sudoers"
    print_info "Передайте этот файл службе безопасности для настройки прав"
}

# Функция для безопасной настройки iptables
safe_configure_iptables() {
    print_step "Настройка iptables для мониторинговых портов"
    
    local ports=("$PROMETHEUS_PORT" "$GRAFANA_PORT" "12990" "12991")
    
    for port in "${ports[@]}"; do
        if [[ -n "$port" ]]; then
            print_info "Открытие порта $port в iptables"
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        fi
    done
    
    # Сохраняем правила iptables
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/sysconfig/iptables
        print_success "Правила iptables сохранены"
    fi
    
    print_success "Настройка iptables завершена"
}

# Основная функция с полной логикой развертывания
main() {
    log_message "=== Начало развертывания мониторинговой системы v4.0 (Security Enhanced - Full) ==="
    
    ensure_working_directory
    print_header
    check_sudo
    check_dependencies
    safe_detect_network_info
    
    # Устанавливаем скрипты-обертки
    install_wrapper_scripts
    
    # Подготавливаем шаблон sudoers для службы безопасности
    configure_sudoers
    
    # Полная логика развертывания:
    print_step "Начало полного развертывания мониторинговой системы"
    
    # Здесь будет полная логика развертывания:
    # - Установка Vault через RLM
    # - Настройка конфигурационных файлов
    # - Установка и настройка сервисов
    # - Настройка iptables
    # - Импорт Grafana дашбордов
    # - Проверка установки
    
    # Временно - базовая настройка iptables
    safe_configure_iptables
    
    # Очистка чувствительных данных
    cleanup_sensitive_data
    
    print_success "Предварительная настройка завершена!"
    print_info "Для полного развертывания необходимо добавить логику установки RLM, Vault и сервисов"
    print_info "После настройки прав службой безопасности запустите скрипт снова"
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
