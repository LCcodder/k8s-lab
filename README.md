<div align="center">

# ⚓ k8s-lab

**Домашняя лаборатория: k3s-кластер на одном сервере, развёрнутый через Ansible,<br>с микросервисами на Kafka и MySQL, Helm-чартами и Nginx на входе.**

<p>
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
  <img src="https://img.shields.io/badge/k3s-FFC61C?style=for-the-badge&logo=k3s&logoColor=black" alt="k3s"/>
  <img src="https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white" alt="Helm"/>
  <img src="https://img.shields.io/badge/Ansible-EE0000?style=for-the-badge&logo=ansible&logoColor=white" alt="Ansible"/>
  <img src="https://img.shields.io/badge/Nginx-009639?style=for-the-badge&logo=nginx&logoColor=white" alt="Nginx"/>
  <img src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"/>
  <img src="https://img.shields.io/badge/Ubuntu_Server-E95420?style=for-the-badge&logo=ubuntu&logoColor=white" alt="Ubuntu"/>
</p>
<p>
  <img src="https://img.shields.io/badge/Apache_Kafka-231F20?style=for-the-badge&logo=apachekafka&logoColor=white" alt="Apache Kafka"/>
  <img src="https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white" alt="MySQL"/>
  <img src="https://img.shields.io/badge/Go-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go"/>
  <img src="https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=nodedotjs&logoColor=white" alt="Node.js"/>
  <img src="https://img.shields.io/badge/Telegram_Bot-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram"/>
  
</p>

</div>


## О проекте

Учебный стенд, на котором отрабатывается весь путь от «голого» Ubuntu-сервера до работающих микросервисов:

1. **Ansible** готовит сервер: обновляет пакеты, ставит Docker, k3s, Nginx и клонирует репозитории.
2. **k3s** поднимает одноузловой Kubernetes-кластер. NodePort-ы слушают только `127.0.0.0/8`, поэтому наружу они не торчат.
3. **Манифесты и Helm-чарты** разворачивают в кластере MySQL, Kafka (KRaft), producer-API и Telegram consumer-бота.
4. **Nginx** на хосте проксирует Kubernetes Dashboard (по TLS) и Kafka UI.

Предметная область приложения — агрегатор баскетбольных матчей (БД `basketball_aggregator`): команды, игроки, игры и подписки пользователей на них.


## Архитектура

```mermaid
flowchart LR
    user([Клиент])
    tg([Telegram])

    subgraph host["Ubuntu Server"]
        nginx["Nginx<br/>:2064 TLS · :2065"]
        kui["Kafka UI<br/>127.0.0.1:8080"]

        subgraph k3s["k3s · namespace kafka-template"]
            api["producer-api<br/>×5 replicas · NodePort 30080"]
            kafka[("Kafka KRaft<br/>StatefulSet")]
            bot["consumer-bot<br/>×1"]
            mysql[("MySQL 8.4<br/>StatefulSet")]
        end

        dash["Kubernetes Dashboard<br/>NodePort 30443"]
    end

    user -->|HTTPS :2064| nginx --> dash
    user -->|:2065| nginx --> kui
    user -->|через nginx| api
    kui -->|127.0.0.1:30092| kafka
    api -->|produce| kafka
    kafka -->|consume| bot
    api --> mysql
    bot --> mysql
    bot <--> tg
```



## Быстрый старт

### 1. Подготовка сервера (Ansible)

```bash
cd ansible
ansible-galaxy collection install -r requirements.yaml

# Нужные роли раскомментируй в site.yaml
ansible-playbook site.yaml --ask-vault-pass
```

Выборочный запуск по тегам:

```bash
ansible-playbook site.yaml --tags k3s            --ask-vault-pass   # k3s + Helm + Dashboard
ansible-playbook site.yaml --tags k3s_dashboard  --ask-vault-pass   # только Dashboard
ansible-playbook site.yaml --tags nginx_cert     --ask-vault-pass   # только сертификат
ansible-playbook site.yaml --check --diff        --ask-vault-pass   # сухой прогон
```

> Для `group_vars/vault.yml` (зашифрован через `ansible-vault`) нужны переменные с SSH- и sudo-паролями (`vault_lafazan_lab_ssh_password`, `vault_lafazan_lab_become_password`) и GitHub-токеном для роли `repository`.

### 2. Деплой приложения (k3s)

```bash
cd k8s
cp .env.example .env            # заполни значения

# Неймспейс, секреты, конфиги
kubectl apply -f namespace.yaml
kubectl -n kafka-template create secret generic app-secrets --from-env-file=.env
kubectl -n kafka-template create configmap mysql-init --from-file=init.sql=scripts/init.sql
kubectl apply -f configmap.yaml

# MySQL и Kafka
kubectl apply -f mysql/ -f kafka/
kubectl -n kafka-template rollout status statefulset/mysql --timeout=300s
kubectl -n kafka-template rollout status statefulset/kafka --timeout=300s

# API и бот (тег образа обязателен)
helm upgrade --install producer-api ./charts/api -n kafka-template --set image.tag=v1.0.0 --atomic
helm upgrade --install consumer-bot ./charts/bot -n kafka-template --set image.tag=v1.0.0 --atomic
```

Подробности, откат и отладка: [`k8s/README.md`](k8s/README.md).


## Ansible-роли

| Роль | Что делает |
|---|---|
| `packages` | `apt dist-upgrade`, autoremove, проверка необходимости перезагрузки |
| `docker` | Docker Engine и плагины, standalone Compose, LazyDocker, cron-очистка билд-кеша |
| `repository` | Ставит git и клонирует список репозиториев в `/root/lab` |
| `nginx` | Устанавливает Nginx, генерирует самоподписанный сертификат с SAN для Dashboard |
| `k3s` | Устанавливает k3s с ограничением NodePort на loopback, Helm и Kubernetes Dashboard |


### Вход в Kubernetes Dashboard

```bash
# токен для ServiceAccount admin-user (создаётся ролью k3s)
kubectl -n kubernetes-dashboard create token admin-user --duration=24h
```


## Выкатка и откат

```bash
# Новая версия (теги только конкретные, не latest)
docker build -t lccodder/kafka-template-producer:v1.0.1 ./producer
docker push  lccodder/kafka-template-producer:v1.0.1
helm upgrade --install producer-api ./charts/api -n kafka-template --set image.tag=v1.0.1 --atomic

# Откат
helm history  producer-api -n kafka-template
helm rollback producer-api -n kafka-template        # на предыдущую ревизию
```

`--atomic` ждёт готовности подов и при провале сам откатывает релиз. `producer-api` обновляется через `RollingUpdate` (`maxUnavailable: 0`), без простоя.
