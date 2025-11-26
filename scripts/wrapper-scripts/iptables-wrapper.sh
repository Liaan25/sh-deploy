#!/bin/bash
set -euo pipefail

# Скрипт-обертка для iptables с валидацией входных параметров
# Использует белые списки для проверки разрешенных портов и источников

# Белый список разрешенных портов
ALLOWED_PORTS=("9090" "3000" "12990" "12991" "13000:14000")
ALLOWED_SOURCES=("127.0.0.1" "localhost")

# Функция валидации порта
validate_port() {
    local port="$1"
    
    # Проверяем диапазон портов
    if [[ "$port" == *":"* ]]; then
        local start_port="${port%:*}"
        local end_port="${port#*:}"
        
        # Проверяем что это числа
        if ! [[ "$start_port" =~ ^[0-9]+$ ]] || ! [[ "$end_port" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Invalid port range format: $port" >&2
            return 1
        fi
        
        # Проверяем что диапазон разрешен
        for allowed in "${ALLOWED_PORTS[@]}"; do
            if [[ "$allowed" == "$port" ]]; then
                return 0
            fi
        done
    else
        # Проверяем одиночный порт
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            echo "ERROR: Invalid port: $port" >&2
            return 1
        fi
        
        # Проверяем что порт разрешен
        for allowed in "${ALLOWED_PORTS[@]}"; do
            if [[ "$allowed" == "$port" ]] || [[ "$allowed" == *":"* && "$port" -ge "${allowed%:*}" && "$port" -le "${allowed#*:}" ]]; then
                return 0
            fi
        done
    fi
    
    echo "ERROR: Port $port not in allowed list: ${ALLOWED_PORTS[*]}" >&2
    return 1
}

# Функция валидации источника
validate_source() {
    local source="$1"
    
    # Проверяем IP адрес или localhost
    for allowed in "${ALLOWED_SOURCES[@]}"; do
        if [[ "$source" == "$allowed" ]]; then
            return 0
        fi
    done
    
    # Дополнительная проверка для IP адреса сервера (будет заменен на реальный IP)
    if [[ "$source" == "SERVER_IP" ]]; then
        return 0
    fi
    
    echo "ERROR: Source $source not in allowed list: ${ALLOWED_SOURCES[*]}" >&2
    return 1
}

# Функция логирования
log_wrapper_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] IPTABLES_WRAPPER: $*" >> /var/log/monitoring-wrapper.log 2>/dev/null || true
}

# Основная логика
case "${1:-}" in
    "add-prometheus-rule")
        local source="$2"
        local port="$3"
        
        log_wrapper_action "Adding prometheus rule: source=$source, port=$port"
        
        validate_source "$source"
        validate_port "$port"
        
        /usr/sbin/iptables -I INPUT -p tcp -s "$source" --dport "$port" -j ACCEPT
        log_wrapper_action "Prometheus rule added successfully"
        ;;
        
    "add-grafana-rule")
        local port="$2"
        
        log_wrapper_action "Adding grafana rule: port=$port"
        
        validate_port "$port"
        
        /usr/sbin/iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        log_wrapper_action "Grafana rule added successfully"
        ;;
        
    "add-harvest-rule")
        local port="$2"
        
        log_wrapper_action "Adding harvest rule: port=$port"
        
        validate_port "$port"
        
        /usr/sbin/iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        log_wrapper_action "Harvest rule added successfully"
        ;;
        
    "add-port-range")
        local range="$2"
        
        log_wrapper_action "Adding port range: range=$range"
        
        validate_port "$range"
        
        /usr/sbin/iptables -A INPUT -p tcp --dport "$range" -j ACCEPT
        log_wrapper_action "Port range added successfully"
        ;;
        
    "check-rule")
        local source="${2:-}"
        local port="$3"
        
        if [[ -n "$source" ]]; then
            validate_source "$source"
            validate_port "$port"
            /usr/sbin/iptables -C INPUT -p tcp -s "$source" --dport "$port" -j ACCEPT
        else
            validate_port "$port"
            /usr/sbin/iptables -C INPUT -p tcp --dport "$port" -j ACCEPT
        fi
        ;;
        
    "reject-rule")
        local port="$2"
        
        log_wrapper_action "Adding reject rule: port=$port"
        
        validate_port "$port"
        
        /usr/sbin/iptables -A INPUT -p tcp --dport "$port" -j REJECT
        log_wrapper_action "Reject rule added successfully"
        ;;
        
    *)
        echo "ERROR: Unknown command. Available commands:" >&2
        echo "  add-prometheus-rule <source> <port>" >&2
        echo "  add-grafana-rule <port>" >&2
        echo "  add-harvest-rule <port>" >&2
        echo "  add-port-range <range>" >&2
        echo "  check-rule [source] <port>" >&2
        echo "  reject-rule <port>" >&2
        exit 1
        ;;
esac
