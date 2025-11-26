#!/bin/bash
set -euo pipefail

# Скрипт-обертка для curl с валидацией URL и параметров
# Использует белые списки для проверки разрешенных доменов

# Белый список разрешенных доменов
ALLOWED_DOMAINS=("simple-api.rlm.apps.prom-terra000049-ebm.ocp.sigma.sbrf.ru" "infra.nexus.sigma.sbrf.ru")

# Функция валидации URL
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

# Функция валидации task_id
validate_task_id() {
    local task_id="$1"
    
    # Проверяем что task_id состоит только из цифр
    if ! [[ "$task_id" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid task_id format: $task_id" >&2
        return 1
    fi
    
    # Проверяем длину task_id (обычно 1-10 цифр)
    if [[ ${#task_id} -lt 1 || ${#task_id} -gt 10 ]]; then
        echo "ERROR: task_id length invalid: $task_id" >&2
        return 1
    fi
    
    return 0
}

# Функция логирования
log_wrapper_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CURL_WRAPPER: $*" >> /var/log/monitoring-wrapper.log 2>/dev/null || true
}

# Функция безопасной очистки переменных
cleanup_sensitive_data() {
    local token="$1"
    # Перезаписываем переменную пустой строкой
    token=""
}

# Основная логика
case "${1:-}" in
    "rlm-api-post")
        local url="$2"
        local token="$3"
        local payload="$4"
        
        log_wrapper_action "RLM API POST to: $(echo "$url" | sed 's|https://||' | cut -d'/' -f1)"
        
        validate_url "$url"
        
        # Выполняем запрос
        local response
        response=$(/usr/bin/curl -k -s -X POST "$url" \
            -H "Accept: application/json" \
            -H "Authorization: Token $token" \
            -H "Content-Type: application/json" \
            -d "$payload")
        
        # Очищаем чувствительные данные
        cleanup_sensitive_data "$token"
        
        echo "$response"
        log_wrapper_action "RLM API POST completed"
        ;;
        
    "rlm-api-get")
        local url="$2"
        local token="$3"
        
        log_wrapper_action "RLM API GET to: $(echo "$url" | sed 's|https://||' | cut -d'/' -f1)"
        
        validate_url "$url"
        
        # Проверяем task_id в URL если есть
        if [[ "$url" =~ /tasks/([0-9]+)/ ]]; then
            local task_id="${BASH_REMATCH[1]}"
            validate_task_id "$task_id"
        fi
        
        # Выполняем запрос
        local response
        response=$(/usr/bin/curl -k -s -X GET "$url" \
            -H "Accept: application/json" \
            -H "Authorization: Token $token" \
            -H "Content-Type: application/json")
        
        # Очищаем чувствительные данные
        cleanup_sensitive_data "$token"
        
        echo "$response"
        log_wrapper_action "RLM API GET completed"
        ;;
        
    "download-rpm")
        local url="$2"
        local output_file="$3"
        
        log_wrapper_action "Downloading RPM: $(basename "$output_file")"
        
        validate_url "$url"
        
        # Проверяем что файл имеет расширение .rpm
        if [[ ! "$output_file" =~ \.rpm$ ]]; then
            echo "ERROR: Output file must have .rpm extension: $output_file" >&2
            exit 1
        fi
        
        # Проверяем путь для сохранения
        if [[ ! "$output_file" =~ ^/opt/mon_distrib/mon_rpm_ ]]; then
            echo "ERROR: RPM must be saved to /opt/mon_distrib/mon_rpm_* directory" >&2
            exit 1
        fi
        
        /usr/bin/curl -k -s -L -o "$output_file" "$url"
        log_wrapper_action "RPM download completed"
        ;;
        
    *)
        echo "ERROR: Unknown command. Available commands:" >&2
        echo "  rlm-api-post <url> <token> <payload>" >&2
        echo "  rlm-api-get <url> <token>" >&2
        echo "  download-rpm <url> <output_file>" >&2
        exit 1
        ;;
esac
