#!/bin/bash
set -euo pipefail

# Скрипт-обертка для операций с файлами с валидацией путей
# Использует белые списки для проверки разрешенных файлов

# Белый список разрешенных файлов
ALLOWED_FILES=(
    "/etc/environment.d/99-monitoring-vars.conf"
    "/opt/vault/conf/agent.hcl"
    "/etc/grafana/grafana.ini"
    "/etc/prometheus/web-config.yml"
    "/etc/prometheus/prometheus.env"
    "/etc/profile.d/harvest.sh"
    "/opt/harvest/harvest.yml"
    "/etc/systemd/system/harvest.service"
    "/var/lib/monitoring_deployment_state"
    "/etc/prometheus/prometheus.yml"
    "/opt/harvest/cert/harvest.crt"
    "/opt/harvest/cert/harvest.key"
    "/etc/grafana/cert/crt.crt"
    "/etc/grafana/cert/key.key"
    "/etc/prometheus/cert/server.crt"
    "/etc/prometheus/cert/server.key"
    "/etc/prometheus/cert/ca_chain.crt"
)

# Функция валидации файла
validate_file() {
    local file="$1"
    
    # Проверяем что файл в белом списке
    for allowed in "${ALLOWED_FILES[@]}"; do
        if [[ "$file" == "$allowed" ]]; then
            return 0
        fi
    done
    
    echo "ERROR: File $file not in allowed list" >&2
    return 1
}

# Функция валидации директории
validate_directory() {
    local dir="$1"
    
    # Разрешенные директории
    local allowed_dirs=(
        "/etc/environment.d"
        "/opt/vault/conf"
        "/etc/grafana"
        "/etc/prometheus"
        "/etc/profile.d"
        "/opt/harvest"
        "/etc/systemd/system"
        "/var/lib"
        "/opt/harvest/cert"
        "/etc/grafana/cert"
        "/etc/prometheus/cert"
    )
    
    for allowed_dir in "${allowed_dirs[@]}"; do
        if [[ "$dir" == "$allowed_dir" ]]; then
            return 0
        fi
    done
    
    echo "ERROR: Directory $dir not allowed" >&2
    return 1
}

# Функция логирования
log_wrapper_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FILE_OPS_WRAPPER: $*" >> /var/log/monitoring-wrapper.log 2>/dev/null || true
}

# Основная логика
case "${1:-}" in
    "create-file")
        local file="$2"
        local content="$3"
        
        log_wrapper_action "Creating file: $file"
        
        validate_file "$file"
        
        # Создаем директорию если нужно
        local dir
        dir=$(dirname "$file")
        if [[ ! -d "$dir" ]]; then
            validate_directory "$dir"
            mkdir -p "$dir"
        fi
        
        # Создаем файл
        echo "$content" > "$file"
        
        # Устанавливаем правильные права в зависимости от типа файла
        case "$file" in
            */cert/*.key | */cert/*.pem)
                chmod 600 "$file"
                ;;
            */cert/*.crt | */cert/*.pem)
                chmod 644 "$file"
                ;;
            */grafana/*.ini | */prometheus/*.yml | */prometheus/*.env)
                chmod 640 "$file"
                ;;
            */profile.d/*.sh)
                chmod 755 "$file"
                ;;
            *)
                chmod 644 "$file"
                ;;
        esac
        
        log_wrapper_action "File created: $file"
        ;;
        
    "append-file")
        local file="$2"
        local content="$3"
        
        log_wrapper_action "Appending to file: $file"
        
        validate_file "$file"
        
        echo "$content" >> "$file"
        log_wrapper_action "Content appended to: $file"
        ;;
        
    "create-directory")
        local dir="$2"
        
        log_wrapper_action "Creating directory: $dir"
        
        validate_directory "$dir"
        
        mkdir -p "$dir"
        log_wrapper_action "Directory created: $dir"
        ;;
        
    "change-owner")
        local file="$2"
        local owner="$3"
        
        log_wrapper_action "Changing owner: $file -> $owner"
        
        validate_file "$file"
        
        # Проверяем что владелец существует
        if ! id "$owner" &>/dev/null; then
            echo "ERROR: User $owner does not exist" >&2
            exit 1
        fi
        
        chown "$owner" "$file"
        log_wrapper_action "Owner changed: $file -> $owner"
        ;;
        
    "change-permissions")
        local file="$2"
        local permissions="$3"
        
        log_wrapper_action "Changing permissions: $file -> $permissions"
        
        validate_file "$file"
        
        # Проверяем формат прав доступа
        if ! [[ "$permissions" =~ ^[0-7]{3,4}$ ]]; then
            echo "ERROR: Invalid permissions format: $permissions" >&2
            exit 1
        fi
        
        chmod "$permissions" "$file"
        log_wrapper_action "Permissions changed: $file -> $permissions"
        ;;
        
    *)
        echo "ERROR: Unknown command. Available commands:" >&2
        echo "  create-file <file> <content>" >&2
        echo "  append-file <file> <content>" >&2
        echo "  create-directory <directory>" >&2
        echo "  change-owner <file> <owner>" >&2
        echo "  change-permissions <file> <permissions>" >&2
        exit 1
        ;;
esac

