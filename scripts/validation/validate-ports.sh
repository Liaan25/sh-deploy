#!/bin/bash
set -euo pipefail

# Скрипт валидации портов для использования в скриптах-обертках

# Белый список разрешенных портов
ALLOWED_PORTS=("9090" "3000" "12990" "12991" "13000:14000")

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
        
        # Проверяем что порт в допустимом диапазоне
        if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            echo "ERROR: Port $port out of range (1-65535)" >&2
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

# Если скрипт вызван напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <port>"
        exit 1
    fi
    
    validate_port "$1"
    exit $?
fi

