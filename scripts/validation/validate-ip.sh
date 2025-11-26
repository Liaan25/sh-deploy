#!/bin/bash
set -euo pipefail

# Скрипт валидации IP адресов для использования в скриптах-обертках

# Белый список разрешенных источников
ALLOWED_SOURCES=("127.0.0.1" "localhost")

validate_ip() {
    local ip="$1"
    
    # Проверяем localhost
    if [[ "$ip" == "localhost" ]]; then
        return 0
    fi
    
    # Проверяем IPv4 формат
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Проверяем каждую часть IP
        IFS='.' read -r -a ip_parts <<< "$ip"
        for part in "${ip_parts[@]}"; do
            if [[ "$part" -lt 0 || "$part" -gt 255 ]]; then
                echo "ERROR: Invalid IP address: $ip" >&2
                return 1
            fi
        done
        
        # Проверяем что IP в белом списке
        for allowed in "${ALLOWED_SOURCES[@]}"; do
            if [[ "$ip" == "$allowed" ]]; then
                return 0
            fi
        done
        
        # Дополнительная проверка для IP сервера (будет заменен на реальный IP)
        if [[ "$ip" == "SERVER_IP" ]]; then
            return 0
        fi
        
        echo "ERROR: IP $ip not in allowed list: ${ALLOWED_SOURCES[*]}" >&2
        return 1
    else
        echo "ERROR: Invalid IP address format: $ip" >&2
        return 1
    fi
}

# Если скрипт вызван напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <ip_address>"
        exit 1
    fi
    
    validate_ip "$1"
    exit $?
fi
