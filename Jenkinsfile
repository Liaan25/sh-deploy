pipeline {
    agent { label 'linux' }

    parameters {
        string(name: 'SERVER_ADDRESS', defaultValue: params.SERVER_ADDRESS ?: '', description: 'Адрес сервера для подключения по SSH')
        string(name: 'SSH_CREDENTIALS_ID', defaultValue: params.SSH_CREDENTIALS_ID ?: '', description: 'ID Jenkins Credentials (SSH Username with private key)')
        string(name: 'SEC_MAN_ADDR', defaultValue: params.SEC_MAN_ADDR ?: '', description: 'Адрес Vault для SecMan')
        string(name: 'NAMESPACE_CI', defaultValue: params.NAMESPACE_CI ?: '', description: 'Namespace для CI в Vault')
        string(name: 'NETAPP_API_ADDR', defaultValue: params.NETAPP_API_ADDR ?: '', description: 'FQDN/IP NetApp API (например, cl01-mgmt.example.org)')
        string(name: 'GRAFANA_PORT', defaultValue: params.GRAFANA_PORT ?: '3000', description: 'Порт Grafana')
        string(name: 'PROMETHEUS_PORT', defaultValue: params.PROMETHEUS_PORT ?: '9090', description: 'Порт Prometheus')
        string(name: 'RLM_API_URL', defaultValue: params.RLM_API_URL ?: 'https://simple-api.rlm.apps.prom-terra000049-ebm.ocp.sigma.sbrf.ru', description: 'Базовый URL RLM API')
        string(name: 'VAULT_AGENT_KV', defaultValue: params.VAULT_AGENT_KV ?: '', description: 'Путь KV в Vault для AppRole')
        string(name: 'RPM_URL_KV', defaultValue: params.RPM_URL_KV ?: '', description: 'Путь KV в Vault для RPM URL')
        string(name: 'GRAFANA_WEB_KV', defaultValue: params.GRAFANA_WEB_KV ?: '', description: 'Путь KV в Vault для Grafana Web')
        string(name: 'SBERCA_CERT_KV', defaultValue: params.SBERCA_CERT_KV ?: '', description: 'Путь KV в Vault для SberCA Cert')
        string(name: 'ADMIN_EMAIL', defaultValue: params.ADMIN_EMAIL ?: '', description: 'Email администратора для сертификатов')
    }

    environment {
        DATE_INSTALL = sh(script: "date '+%Y%m%d_%H%M%S'", returnStdout: true).trim()
    }

    stages {
        stage('Проверка параметров') {
            steps {
                script {
                    echo "================================================"
                    echo "Целевой сервер: ${params.SERVER_ADDRESS}"
                    echo "SSH Credentials: ${params.SSH_CREDENTIALS_ID}"
                    echo "Версия: Security Enhanced v4.0"
                    echo "RLM API URL: ${params.RLM_API_URL}"
                    echo "================================================"
                    
                    if (!params.SERVER_ADDRESS || !params.SSH_CREDENTIALS_ID) {
                        error("ОШИБКА: Не указаны обязательные параметры (SERVER_ADDRESS или SSH_CREDENTIALS_ID)")
                    }
                }
            }
        }

        stage('Получение данных из Vault') {
            steps {
                script {
                    echo "[STEP] Безопасное получение данных из Vault"
                    
                    // Используем withVault для безопасного получения секретов
                    withVault([
                        configuration: [
                            vaultUrl: "https://${params.SEC_MAN_ADDR}",
                            engineVersion: 1,
                            skipSslVerification: false,
                            vaultCredentialId: 'vault-agent-dev'
                        ],
                        vaultSecrets: [
                            [path: params.VAULT_AGENT_KV, secretValues: [
                                [envVar: 'VA_ROLE_ID', vaultKey: 'role_id'],
                                [envVar: 'VA_SECRET_ID', vaultKey: 'secret_id']
                            ]],
                            [path: params.RPM_URL_KV, secretValues: [
                                [envVar: 'VA_RPM_HARVEST', vaultKey: 'harvest'],
                                [envVar: 'VA_RPM_PROMETHEUS', vaultKey: 'prometheus'],
                                [envVar: 'VA_RPM_GRAFANA', vaultKey: 'grafana']
                            ]],
                            [path: params.GRAFANA_WEB_KV, secretValues: [
                                [envVar: 'VA_GRAFANA_WEB_USER', vaultKey: 'user'],
                                [envVar: 'VA_GRAFANA_WEB_PASS', vaultKey: 'pass']
                            ]]
                        ]
                    ]) {
                        // Создаем временный файл с учетными данными
                        def data = [
                          "vault-agent": [
                            role_id: (env.VA_ROLE_ID ?: ''),
                            secret_id: (env.VA_SECRET_ID ?: '')
                          ],
                          "rpm_url": [
                            harvest: (env.VA_RPM_HARVEST ?: ''),
                            prometheus: (env.VA_RPM_PROMETHEUS ?: ''),
                            grafana: (env.VA_RPM_GRAFANA ?: '')
                          ],
                          "grafana_web": [
                            user: (env.VA_GRAFANA_WEB_USER ?: ''),
                            pass: (env.VA_GRAFANA_WEB_PASS ?: '')
                          ]
                        ]
                        
                        writeFile file: 'temp_data_cred.json', text: groovy.json.JsonOutput.toJson(data)
                    }
                    
                    // Проверяем что файл создан
                    def checkStatus = sh(script: 'test -s temp_data_cred.json', returnStatus: true)
                    if (checkStatus != 0) {
                        error("ОШИБКА: Не удалось получить данные из Vault")
                    }
                    
                    echo "[SUCCESS] Данные из Vault получены безопасно"
                }
            }
        }

        stage('Клонирование репозитория') {
            steps {
                script {
                    echo "[STEP] Клонирование репозитория из Bitbucket"
                    
                    withCredentials([sshUserPrivateKey(credentialsId: 'bitbucket-ssh-dev-ift', keyFileVariable: 'BITBUCKET_SSH_KEY', usernameVariable: 'BITBUCKET_SSH_USER')]) {
                        sh '''
                            # Очищаем существующую директорию если есть
                            if [ -d "monitoring-deployment" ]; then
                                echo "[INFO] Удаляем существующую директорию monitoring-deployment"
                                rm -rf monitoring-deployment
                            fi
                            
                            # Клонируем репозиторий
                            GIT_SSH_COMMAND="ssh -i $BITBUCKET_SSH_KEY -o StrictHostKeyChecking=no" \
                            git clone ssh://git@stash.delta.sbrf.ru:7999/infranas/deploy-mon-sh.git monitoring-deployment
                            
                            # Проверяем что репозиторий склонирован
                            test -d monitoring-deployment && test -f monitoring-deployment/scripts/deploy_monitoring.sh
                        '''
                    }
                    
                    echo "[SUCCESS] Репозиторий успешно клонирован"
                }
            }
        }

        stage('Копирование проекта на сервер') {
            steps {
                script {
                    echo "[STEP] Копирование проекта на сервер ${params.SERVER_ADDRESS}..."
                    
                    withCredentials([
                        sshUserPrivateKey(credentialsId: params.SSH_CREDENTIALS_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER'),
                        sshUserPrivateKey(credentialsId: 'bitbucket-ssh-dev-ift', keyFileVariable: 'BITBUCKET_SSH_KEY', usernameVariable: 'BITBUCKET_SSH_USER'),
                        string(credentialsId: 'rlm-token', variable: 'RLM_TOKEN')
                    ]) {
                        // Создаем скрипт для копирования
                        writeFile file: 'deploy_remote.sh', text: """#!/bin/bash
set -e

# Копируем проект на удаленный сервер
scp -i "\$SSH_KEY" -q -o StrictHostKeyChecking=no -r monitoring-deployment "\$SSH_USER"@${params.SERVER_ADDRESS}:/tmp/
scp -i "\$SSH_KEY" -q -o StrictHostKeyChecking=no temp_data_cred.json "\$SSH_USER"@${params.SERVER_ADDRESS}:/tmp/

# Запускаем развертывание
ssh -i "\$SSH_KEY" -q -o StrictHostKeyChecking=no "\$SSH_USER"@${params.SERVER_ADDRESS} << 'REMOTE_EOF'
set -e

# Переменные окружения для безопасного развертывания
export SEC_MAN_ADDR="${params.SEC_MAN_ADDR}"
export NAMESPACE_CI="${params.NAMESPACE_CI}"
export RLM_API_URL="${params.RLM_API_URL}"
export RLM_TOKEN="\$RLM_TOKEN"
export NETAPP_API_ADDR="${params.NETAPP_API_ADDR}"
export GRAFANA_PORT="${params.GRAFANA_PORT}"
export PROMETHEUS_PORT="${params.PROMETHEUS_PORT}"
export VAULT_AGENT_KV="${params.VAULT_AGENT_KV}"
export RPM_URL_KV="${params.RPM_URL_KV}"
export GRAFANA_WEB_KV="${params.GRAFANA_WEB_KV}"
export SBERCA_CERT_KV="${params.SBERCA_CERT_KV}"
export ADMIN_EMAIL="${params.ADMIN_EMAIL}"

# Извлекаем данные из JSON безопасно
RPM_GRAFANA=\$(jq -r '.rpm_url.grafana // empty' /tmp/temp_data_cred.json)
RPM_PROMETHEUS=\$(jq -r '.rpm_url.prometheus // empty' /tmp/temp_data_cred.json)
RPM_HARVEST=\$(jq -r '.rpm_url.harvest // empty' /tmp/temp_data_cred.json)

# Запускаем скрипт развертывания
cd /tmp/monitoring-deployment/scripts
chmod +x deploy_monitoring.sh
sudo -E ./deploy_monitoring.sh

REMOTE_EOF
"""
                        
                        sh 'chmod +x deploy_remote.sh'
                        withEnv(['SSH_KEY=' + env.SSH_KEY, 'SSH_USER=' + env.SSH_USER, 'BITBUCKET_SSH_KEY=' + env.BITBUCKET_SSH_KEY]) {
                            sh './deploy_remote.sh'
                        }
                        sh 'rm -f deploy_remote.sh'
                    }
                    
                    echo "[SUCCESS] Проект скопирован и запущен на сервере"
                }
            }
        }

        stage('Проверка результатов') {
            steps {
                script {
                    echo "[STEP] Проверка результатов развертывания..."
                    
                    withCredentials([sshUserPrivateKey(credentialsId: params.SSH_CREDENTIALS_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                        writeFile file: 'check_results.sh', text: """#!/bin/bash
ssh -i "\$SSH_KEY" -q -o StrictHostKeyChecking=no \\
    "\$SSH_USER"@${params.SERVER_ADDRESS} << 'ENDSSH'
echo "================================================"
echo "ПРОВЕРКА СЕРВИСОВ (Security Enhanced):"
echo "================================================"

# Проверка через скрипты-обертки
sudo /opt/monitoring/wrappers/systemctl-wrapper.sh is-active prometheus && echo "[OK] Prometheus активен" || echo "[FAIL] Prometheus не активен"
sudo /opt/monitoring/wrappers/systemctl-wrapper.sh is-active grafana-server && echo "[OK] Grafana активен" || echo "[FAIL] Grafana не активен"
sudo /opt/monitoring/wrappers/systemctl-wrapper.sh is-active harvest && echo "[OK] Harvest активен" || echo "[FAIL] Harvest не активен"

echo ""
echo "================================================"
echo "ПРОВЕРКА ПОРТОВ:"
echo "================================================"
ss -tln | grep -q ":${params.PROMETHEUS_PORT} " && echo "[OK] Порт ${params.PROMETHEUS_PORT} (Prometheus) открыт" || echo "[FAIL] Порт ${params.PROMETHEUS_PORT} не открыт"
ss -tln | grep -q ":${params.GRAFANA_PORT} " && echo "[OK] Порт ${params.GRAFANA_PORT} (Grafana) открыт" || echo "[FAIL] Порт ${params.GRAFANA_PORT} не открыт"
ss -tln | grep -q ":12990 " && echo "[OK] Порт 12990 (Harvest-NetApp) открыт" || echo "[FAIL] Порт 12990 не открыт"
ss -tln | grep -q ":12991 " && echo "[OK] Порт 12991 (Harvest-Unix) открыт" || echo "[FAIL] Порт 12991 не открыт"

echo ""
echo "================================================"
echo "ПРОВЕРКА БЕЗОПАСНОСТИ:"
echo "================================================"
# Проверяем что скрипты-обертки установлены
if [ -f "/opt/monitoring/wrappers/iptables-wrapper.sh" ]; then
    echo "[OK] Скрипты-обертки установлены"
else
    echo "[FAIL] Скрипты-обертки не установлены"
fi

# Проверяем что sudoers настроен
if [ -f "/etc/sudoers.d/monitoring-deployment" ]; then
    echo "[OK] Sudoers настроен с NOEXEC"
else
    echo "[FAIL] Sudoers не настроен"
fi

ENDSSH
"""
                        sh 'chmod +x check_results.sh'
                        def result
                        withEnv(['SSH_KEY=' + env.SSH_KEY, 'SSH_USER=' + env.SSH_USER]) {
                            result = sh(script: './check_results.sh', returnStdout: true).trim()
                        }
                        sh 'rm -f check_results.sh'
                        echo result
                    }
                }
            }
        }

        stage('Очистка') {
            steps {
                script {
                    echo "[STEP] Безопасная очистка временных файлов..."
                    
                    // Удаляем временные файлы локально
                    sh "rm -rf temp_data_cred.json monitoring-deployment"
                    
                    // Удаляем временные файлы на удаленном сервере
                    withCredentials([sshUserPrivateKey(credentialsId: params.SSH_CREDENTIALS_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                        writeFile file: 'cleanup_remote.sh', text: """#!/bin/bash
ssh -i "\$SSH_KEY" -q -o StrictHostKeyChecking=no \\
    "\$SSH_USER"@${params.SERVER_ADDRESS} \\
    "rm -rf /tmp/monitoring-deployment /tmp/temp_data_cred.json /opt/mon_distrib/mon_rpm_${env.DATE_INSTALL}/*.rpm" || true
"""
                        sh 'chmod +x cleanup_remote.sh'
                        withEnv(['SSH_KEY=' + env.SSH_KEY, 'SSH_USER=' + env.SSH_USER]) {
                            sh './cleanup_remote.sh'
                        }
                        sh 'rm -f cleanup_remote.sh'
                    }
                    
                    echo "[SUCCESS] Очистка завершена"
                }
            }
        }
    }

    post {
        success {
            echo "================================================"
            echo "✅ Pipeline (Security Enhanced) успешно завершен!"
            echo "================================================"
        }
        failure {
            echo "================================================"
            echo "❌ Pipeline завершился с ошибкой!"
            echo "Проверьте логи для диагностики проблемы"
            echo "================================================"
        }
        always {
            echo "Время выполнения: ${currentBuild.durationString}"
        }
    }
}
