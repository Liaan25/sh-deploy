#!/bin/bash
# Скрипт установки прав доступа для проекта мониторинга
# Версия: 1.1 (обновлен для новой структуры)

set -euo pipefail

echo "================================================="
echo "Установка прав доступа для Monitoring Deployment"
echo "Версия: Security Enhanced v4.0"
echo "================================================="
echo

# Функция для установки прав
set_permissions() {
    local file="$1"
    local permissions="$2"
    
    if [[ -f "$file" ]]; then
        chmod "$permissions" "$file"
        echo "[OK] Установлены права $permissions для $file"
    else
        echo "[WARNING] Файл не найден: $file"
    fi
}

# Функция для установки прав на все файлы в директории
set_permissions_recursive() {
    local dir="$1"
    local pattern="$2"
    local permissions="$3"
    
    if [[ -d "$dir" ]]; then
        find "$dir" -name "$pattern" -type f | while read -r file; do
            chmod "$permissions" "$file"
            echo "[OK] Установлены права $permissions для $file"
        done
    else
        echo "[WARNING] Директория не найдена: $dir"
    fi
}

echo "=== Установка прав на основные скрипты ==="
set_permissions "scripts/deploy_monitoring.sh" "755"

echo
echo "=== Установка прав на скрипты-обертки ==="
set_permissions_recursive "scripts/wrapper-scripts" "*.sh" "755"

echo
echo "=== Установка прав на скрипты валидации ==="
set_permissions_recursive "scripts/validation" "*.sh" "755"

echo
echo "=== Установка прав на конфигурационные файлы ==="
set_permissions "config/sudoers-template" "644"
set_permissions "Jenkinsfile" "644"
set_permissions "README.md" "644"

# Текущий скрипт
set_permissions "setup-permissions.sh" "755"

echo
echo "================================================="
echo "✅ Права доступа успешно установлены!"
echo "================================================="
echo
echo "📋 Проверка структуры проекта:"
find . -type f -name "*.sh" | head -10 | while read -r file; do
    echo "  - $file"
done
echo
echo "🚀 Следующие шаги:"
echo "1. Загрузите проект в Bitbucket"
echo "2. Настройте pipeline в Jenkins с обновленным Jenkinsfile"
echo "3. Убедитесь что credentials настроены правильно:"
echo "   - bitbucket-ssh-dev-ift (для клонирования)"
echo "   - mon-ssh-key-2 (для подключения к серверу)"
echo "   - rlm-token (для RLM API)"
echo "4. Запустите развертывание"
echo
echo "🔍 Для полной проверки прав выполните:"
echo "find . -name '*.sh' -exec ls -la {} \; | head -20"
