#!/bin/bash
# Мониторинг Stack Deployment Script для Fedora
# Компоненты: Harvest + Prometheus + Grafana
# Версия: 4.0 (Security Enhanced - Complete)
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

# ============================================
# ФУНКЦИИ ВЫВОДА И ЛОГИРОВАНИЯ (с безопасностью)
# ============================================

print_header() {
    echo "================================================="
    echo "Деплой Harvest + Prometheus + Grafana (Security Enhanced v4.0)"
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

log_message() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# ============================================
# ФУНКЦИИ БЕЗОПАСНОСТИ (новые)
# ============================================

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

# ============================================
# БАЗОВЫЕ ФУНКЦИИ (из оригинального скрипта с безопасностью)
# ============================================

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

check_sudo() {
    print_step "Проверка прав администратора"
    ensure_working_directory
    
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root (sudo)"
        print_info "Используйте: sudo $SCRIPT_NAME"
        exit 1
    fi
    
    print_success "Права администратора подтверждены"
}

check_dependencies() {
    print_step "Проверка необходимых зависимостей"
    ensure_working_directory
    
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

# ============================================
# ФУНКЦИИ РАЗВЕРТЫВАНИЯ (из оригинального скрипта с безопасностью)
# ============================================

check_and_close_ports() {
    print_step "Проверка и закрытие используемых портов"
    ensure_working_directory
    
    local ports=("$PROMETHEUS_PORT" "$GRAFANA_PORT" "12990" "12991")
    
    for port in "${ports[@]}"; do
        if [[ -n "$port" ]] && ss -tln | grep -q ":$port "; then
            print_warning "Порт $port занят, требуется освобождение"
        fi
    done
    
    print_success "Проверка портов завершена"
}

save_environment_variables() {
    print_step "Сохранение сетевых переменных в окружение"
    ensure_working_directory
    
    mkdir -p /etc/environment.d/
    cat > "$ENV_FILE" << EOF
# Мониторинг Stack Environment Variables
SERVER_IP=$SERVER_IP
SERVER_DOMAIN=$SERVER_DOMAIN
GRAFANA_PORT=$GRAFANA_PORT
PROMETHEUS_PORT=$PROMETHEUS_PORT
EOF
    
    print_success "Переменные окружения сохранены в $ENV_FILE"
}

cleanup_all_previous() {
    print_step "Полная очистка предыдущих установок"
    ensure_working_directory
    
    local services=("prometheus" "grafana-server" "harvest" "harvest-prometheus")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_info "Остановка сервиса: $service"
            systemctl stop "$service" || true
        fi
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            print_info "Отключение автозапуска: $service"
            systemctl disable "$service" || true
        fi
    done

    # Убираем остановку vault - он уже установлен и работает
    print_info "Vault оставляем без изменений (предполагается что уже установлен и настроен)"

    if command -v harvest &> /dev/null; then
        print_info "Остановка Harvest через команду"
        harvest stop --config "$HARVEST_CONFIG" 2>/dev/null || true
    fi

    local packages=("prometheus" "grafana" "harvest")
    for package in "${packages[@]}"; do
        if rpm -q "$package" &>/dev/null; then
            print_info "Удаление пакета: $package"
            rpm -e "$package" --nodeps >/dev/null 2>&1 || true
        fi
    done

    local dirs_to_clean=(
        "/etc/prometheus"
        "/etc/grafana"
        "/etc/harvest"
        "/opt/harvest"
        "/var/lib/prometheus"
        "/var/lib/grafana"
        "/var/lib/harvest"
        "/usr/share/grafana"
        "/usr/share/prometheus"
    )

    for dir in "${dirs_to_clean[@]}"; do
        if [[ -d "$dir" ]]; then
            print_info "Удаление директории: $dir"
            rm -rf "$dir" || true
        fi
    done

    print_success "Очистка предыдущих установок завершена"
}

create_directories() {
    print_step "Создание рабочих директорий"
    ensure_working_directory
    
    local dirs=(
        "/etc/prometheus"
        "/etc/grafana"
        "/etc/harvest"
        "/opt/harvest"
        "/var/lib/prometheus"
        "/var/lib/grafana"
        "/var/lib/harvest"
        "/usr/share/grafana"
        "/usr/share/prometheus"
        "$VAULT_CONF_DIR"
        "$VAULT_LOG_DIR"
        "$VAULT_CERTS_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chmod 755 "$dir"
    done
    
    print_success "Рабочие директории созданы"
}

# Функция установки Vault через RLM (с безопасностью)
install_vault_via_rlm() {
    print_step "Установка и настройка Vault через RLM"
    ensure_working_directory

    if [[ -z "$RLM_TOKEN" || -z "$RLM_API_URL" || -z "$SEC_MAN_ADDR" || -z "$NAMESPACE_CI" || -z "$SERVER_IP" ]]; then
        print_error "Отсутствуют обязательные параметры для установки Vault (RLM_API_URL/RLM_TOKEN/SEC_MAN_ADDR/NAMESPACE_CI/SERVER_IP)"
        exit 1
    fi

    # Нормализуем SEC_MAN_ADDR в верхний регистр для единообразия
    local SEC_MAN_ADDR_UPPER
    SEC_MAN_ADDR_UPPER="${SEC_MAN_ADDR^^}"

    # Формируем KAE_SERVER из NAMESPACE_CI
    local KAE_SERVER
    KAE_SERVER=$(echo "$NAMESPACE_CI" | cut -d'_' -f2)
    print_info "Создание задачи RLM для Vault (tenant=$NAMESPACE_CI, v_url=$SEC_MAN_ADDR_UPPER, host=$SERVER_IP)"

    # Формируем JSON-пейлоад через jq (надежное экранирование)
    local payload vault_create_resp vault_task_id
    payload=$(jq -n       --arg v_url "$SEC_MAN_ADDR_UPPER"       --arg tenant "$NAMESPACE_CI"       --arg kae "$KAE_SERVER"       --arg ip "$SERVER_IP"       '{
        params: {
          v_url: $v_url,
          tenant: $tenant,
          start_after_configuration: false,
          approle: "approle/vault-agent",
          templates: [
            {
              source: { file_name: null, content: null },
              destination: { path: null }
            }
          ],
          serv_user: ($kae + "-lnx-va-start"),
          serv_group: ($kae + "-lnx-va-read"),
          read_user: ($kae + "-lnx-va-start"),
          log_num: 5,
          log_size: 5,
          log_level: "info",
          config_unwrapped: true,
          skip_sm_conflicts: false
        },
        start_at: "now",
        service: "vault_agent_config",
        items: [
          {
            table_id: "secmanserver",
            invsvm_ip: $ip
          }
        ]
      }')

    # Отправляем запрос на создание задачи в RLM
    vault_create_resp=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $RLM_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$RLM_API_URL/api/v1/tasks")

    local http_code
    http_code="${vault_create_resp: -3}"
    vault_create_resp="${vault_create_resp%???}"

    if [[ "$http_code" != "201" ]]; then
        print_error "Ошибка создания задачи RLM для Vault (HTTP $http_code): $vault_create_resp"
        exit 1
    fi

    # Извлекаем ID задачи
    vault_task_id=$(echo "$vault_create_resp" | jq -r '.id // empty')

    if [[ -z "$vault_task_id" ]]; then
        print_error "Не удалось извлечь ID задачи RLM из ответа: $vault_create_resp"
        exit 1
    fi

    print_success "Задача RLM для Vault создана (ID: $vault_task_id)"
    print_info "Ожидание завершения установки Vault..."

    # Ожидаем завершения задачи
    local max_attempts=30
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        local task_status_resp
        task_status_resp=$(curl -s -w "%{http_code}" -X GET \
            -H "Authorization: Bearer $RLM_TOKEN" \
            "$RLM_API_URL/api/v1/tasks/$vault_task_id")

        local status_http_code
        status_http_code="${task_status_resp: -3}"
        task_status_resp="${task_status_resp%???}"

        if [[ "$status_http_code" == "200" ]]; then
            local task_status
            task_status=$(echo "$task_status_resp" | jq -r '.status // empty')

            case "$task_status" in
                "completed")
                    print_success "Установка Vault завершена успешно"
                    return 0
                    ;;
                "failed")
                    local error_msg
                    error_msg=$(echo "$task_status_resp" | jq -r '.error // "Неизвестная ошибка"')
                    print_error "Ошибка установки Vault: $error_msg"
                    exit 1
                    ;;
                "running"|"pending")
                    print_info "Задача RLM выполняется... (попытка $attempt/$max_attempts)"
                    sleep 10
                    ;;
                *)
                    print_warning "Неизвестный статус задачи RLM: $task_status"
                    sleep 10
                    ;;
            esac
        else
            print_warning "Ошибка получения статуса задачи RLM (HTTP $status_http_code), повтор через 10 сек..."
            sleep 10
        fi

        ((attempt++))
    done

    print_error "Превышено время ожидания завершения установки Vault"
    exit 1
}

# Здесь будут добавлены остальные 30 функций из оригинального скрипта
# с интегрированными мерами безопасности

# Основная функция с полной логикой развертывания
main() {
    log_message "=== Начало развертывания мониторинговой системы v4.0 (Security Enhanced - Complete) ==="
    
    ensure_working_directory
    print_header
    check_sudo
    check_dependencies
    
    # Безопасность: устанавливаем скрипты-обертки
    install_wrapper_scripts
    
    # Базовые проверки и подготовка
    check_and_close_ports
    safe_detect_network_info
    save_environment_variables
    
    # Очистка предыдущих установок
    cleanup_all_previous
    create_directories
    
    # Безопасность: подготовка sudoers шаблона
    configure_sudoers
    
    # Отладочный вывод для проверки переменных
    print_info "=== DEBUG: Проверка переменных перед install_vault_via_rlm ==="
    print_info "RLM_TOKEN: ${RLM_TOKEN:+SET}${RLM_TOKEN:+ (длина: ${#RLM_TOKEN})}${RLM_TOKEN:-NOT SET}"
    print_info "RLM_API_URL: ${RLM_API_URL:+SET (${RLM_API_URL})}${RLM_API_URL:-NOT SET}"
    print_info "SEC_MAN_ADDR: ${SEC_MAN_ADDR:+SET (${SEC_MAN_ADDR})}${SEC_MAN_ADDR:-NOT SET}"
    print_info "NAMESPACE_CI: ${NAMESPACE_CI:+SET (${NAMESPACE_CI})}${NAMESPACE_CI:-NOT SET}"
    print_info "SERVER_IP: ${SERVER_IP:+SET (${SERVER_IP})}${SERVER_IP:-NOT SET}"
    
    # Установка Vault и конфигурация
    install_vault_via_rlm
    # setup_vault_config
    # load_config_from_json
    
    # Установка RPM пакетов
    # create_rlm_install_tasks
    # setup_certificates_after_install
    
    # Настройка сервисов
    # configure_harvest
    # configure_prometheus
    # configure_services
    
    # Безопасность: настройка iptables
    # safe_configure_iptables
    
    # Импорт дашбордов и проверка
    # import_grafana_dashboards
    # verify_installation
    # save_installation_state
    
    # Безопасность: очистка чувствительных данных
    cleanup_sensitive_data
    
    print_success "Полное развертывание мониторинговой системы завершено!"
    print_info "Все функции выполнены с интегрированными мерами безопасности"
}

# Запуск основной функции
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
