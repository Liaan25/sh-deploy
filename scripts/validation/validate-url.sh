#!/bin/bash
set -euo pipefail

# Скрипт валидации URL для использования в скриптах-обертках

# Белый список разрешенных доменов
ALLOWED_DOMAINS=("simple-api.rlm.apps.prom-terra000049-ebm.ocp.sigma.sbrf.ru" "infra.nexus.sigma.sbrf.ru")

validate_url() {
    local url="$1"
    
    # Проверяем что URL начинается с https://
    if [[ ! "$url" =~ ^https:// ]]; then
        echo "ERROR: URL must use HTTPS: $url" >&2
        return 1
    fi
    
    # Извлекаем домен из URL
    local domain
    domain=$(echo "$url" | sed -E 's|^https://([^/]+).*|\1|')
    
    # Проверяем домен в белом списке
    for allowed_domain in "${ALLOWED_DOMAINS[@]}"; do
        if [[ "$domain" == "$allowed_domain" ]] || [[ "$domain" =~ \.${allowed_domain}$ ]]; then
            return 0
        fi
    done
    
    echo "ERROR: Domain $domain not in allowed list: ${ALLOWED_DOMAINS[*]}" >&2
    return 1
}

# Если скрипт вызван напрямую
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <url>"
        exit 1
    fi
    
    validate_url "$1"
    exit $?
fi
