#!/bin/bash
# Скрипт установки прав доступа для проекта мониторинга
# Версия: 1.0

set -euo pipefail

echo "================================================="
echo "Установка прав доступа для Monitoring Deployment"
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

# Основные скрипты
set_permissions "scripts/deploy_monitoring.sh" "755"

# Скрипты-обертки
for wrapper in scripts/wrapper-scripts/*.sh; do
    set_permissions "$wrapper" "755"
done

# Скрипты валидации
for validation in scripts/validation/*.sh; do
    set_permissions "$validation" "755"
done

# Конфигурационные файлы
set_permissions "config/sudoers-template" "644"
set_permissions "Jenkinsfile" "644"
set_permissions "README.md" "644"

# Текущий скрипт
set_permissions "setup-permissions.sh" "755"

echo
echo "================================================="
echo "Права доступа успешно установлены!"
echo "================================================="
echo
echo "Следующие шаги:"
echo "1. Настройте параметры в Jenkinsfile"
echo "2. Загрузите проект в Bitbucket"
echo "3. Настройте pipeline в Jenkins"
echo "4. Запустите развертывание"
echo
echo "Для проверки прав выполните:"
echo "find . -name '*.sh' -exec ls -la {} \;"
echo
