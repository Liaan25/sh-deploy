#!/bin/bash
# Скрипт установки прав доступа для проекта мониторинга
# Версия: 1.2 (обновлен для плоской структуры)

set -euo pipefail

echo "================================================="
echo "Установка прав доступа для Monitoring Deployment"
echo "Версия: Security Enhanced v4.0 (Flat Structure)"
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

echo "=== Установка прав на основные скрипты в корне ==="
set_permissions "deploy_monitoring.sh" "755"
set_permissions "setup-permissions.sh" "755"

echo
echo "=== Установка прав на скрипты-обертки ==="
set_permissions_recursive "." "*-wrapper.sh" "755"

echo
echo "=== Установка прав на скрипты валидации ==="
set_permissions_recursive "scripts/validation" "*.sh" "755"

echo
echo "=== Установка прав на конфигурационные файлы ==="
set_permissions "sudoers-template" "644"
set_permissions "Jenkinsfile" "644"
set_permissions "README.md" "644"

echo
echo "================================================="
echo "✅ Права доступа успешно установлены!"
echo "================================================="
echo
echo "📋 Структура проекта (плоская):"
find . -maxdepth 1 -type f -name "*.sh" | while read -r file; do
    echo "  - $(basename "$file")"
done
echo
echo "🚀 Следующие шаги:"
echo "1. Загрузите ВСЕ файлы из этой директории в Bitbucket"
echo "2. Настройте pipeline в Jenkins с обновленным Jenkinsfile"
echo "3. Убедитесь что credentials настроены правильно"
echo "4. Запустите развертывание"
echo
echo "💡 Важно: Все файлы должны быть в корне репозитория!"
