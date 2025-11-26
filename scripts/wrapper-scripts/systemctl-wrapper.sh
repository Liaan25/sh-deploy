#!/bin/bash
set -euo pipefail

# Скрипт-обертка для systemctl с валидацией сервисов
# Используется с NOEXEC атрибутом для предотвращения выполнения произвольного кода

# Белый список разрешенных сервисов
ALLOWED_SERVICES=("prometheus" "grafana-server" "harvest" "vault-agent")

# Функция валидации сервиса
validate_service() {
    local service="$1"
    
    # Проверяем что сервис в белом списке
    for allowed in "${ALLOWED_SERVICES[@]}"; do
        if [[ "$service" == "$allowed" ]]; then
            return 0
        fi
    done
    
    echo "ERROR: Service $service not in allowed list: ${ALLOWED_SERVICES[*]}" >&2
    return 1
}

# Функция логирования
log_wrapper_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SYSTEMCTL_WRAPPER: $*" >> /var/log/monitoring-wrapper.log 2>/dev/null || true
}

# Основная логика
case "${1:-}" in
    "status")
        local service="$2"
        
        log_wrapper_action "Checking status of: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl status "$service"
        log_wrapper_action "Status checked for: $service"
        ;;
        
    "start")
        local service="$2"
        
        log_wrapper_action "Starting service: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl start "$service"
        log_wrapper_action "Service started: $service"
        ;;
        
    "stop")
        local service="$2"
        
        log_wrapper_action "Stopping service: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl stop "$service"
        log_wrapper_action "Service stopped: $service"
        ;;
        
    "restart")
        local service="$2"
        
        log_wrapper_action "Restarting service: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl restart "$service"
        log_wrapper_action "Service restarted: $service"
        ;;
        
    "enable")
        local service="$2"
        
        log_wrapper_action "Enabling service: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl enable "$service"
        log_wrapper_action "Service enabled: $service"
        ;;
        
    "disable")
        local service="$2"
        
        log_wrapper_action "Disabling service: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl disable "$service"
        log_wrapper_action "Service disabled: $service"
        ;;
        
    "is-active")
        local service="$2"
        
        log_wrapper_action "Checking if active: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl is-active "$service"
        log_wrapper_action "Active status checked for: $service"
        ;;
        
    "is-enabled")
        local service="$2"
        
        log_wrapper_action "Checking if enabled: $service"
        
        validate_service "$service"
        
        /usr/bin/systemctl is-enabled "$service"
        log_wrapper_action "Enabled status checked for: $service"
        ;;
        
    "daemon-reload")
        log_wrapper_action "Reloading systemd daemon"
        
        /usr/bin/systemctl daemon-reload
        log_wrapper_action "Systemd daemon reloaded"
        ;;
        
    *)
        echo "ERROR: Unknown command. Available commands:" >&2
        echo "  status <service>" >&2
        echo "  start <service>" >&2
        echo "  stop <service>" >&2
        echo "  restart <service>" >&2
        echo "  enable <service>" >&2
        echo "  disable <service>" >&2
        echo "  is-active <service>" >&2
        echo "  is-enabled <service>" >&2
        echo "  daemon-reload" >&2
        exit 1
        ;;
esac
