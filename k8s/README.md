## Установка

## Дэшборд

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace --namespace kubernetes-dashboard \
  --set kong.proxy.type=NodePort \
  --set kong.proxy.tls.nodePort=30443
```

```
kubectl -n kubernetes-dashboard create token admin-user --duration=2400h
```

```
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/dashboard.key -out /etc/nginx/dashboard.crt \
  -subj "/CN=93.170.246.84"
```

## Первый запуск по шагам

```bash
# неймспейс
kubectl apply -f namespace.yaml


kubectl create secret generic singbox-config \
  -n kafka-template \
  --from-file=config.json=./singbox/singbox-config.json


# .env -> Secret app-secrets
kubectl -n kafka-template create secret generic app-secrets --from-env-file=.env

# init.sql -> ConfigMap mysql-init
kubectl -n kafka-template create configmap mysql-init --from-file=init.sql=scripts/init.sql

# app-config и kafka-config
kubectl apply -f configmap.yaml

# mysql и kafka
kubectl apply -f mysql/ -f kafka/

# дождаться готовности
kubectl -n kafka-template rollout status statefulset/mysql --timeout=300s
kubectl -n kafka-template rollout status statefulset/kafka --timeout=300s

# api и бот
helm upgrade --install producer-api ./charts/api -n kafka-template --set image.tag=v1.0.0 --atomic
helm upgrade --install consumer-bot ./charts/bot -n kafka-template --set image.tag=v1.0.0 --atomic
```

## Запуск одним скриптом (deploy.sh)

Идемпотентный: можно запускать повторно.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

NS=kafka-template
API_TAG=${1:?usage: ./deploy.sh <api-tag> <bot-tag>}
BOT_TAG=${2:?usage: ./deploy.sh <api-tag> <bot-tag>}

kubectl apply -f namespace.yaml
kubectl -n $NS create secret generic app-secrets --from-env-file=.env \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n $NS create configmap mysql-init --from-file=init.sql=scripts/init.sql \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f configmap.yaml
kubectl apply -f mysql/ -f kafka/

kubectl -n $NS rollout status statefulset/mysql --timeout=300s
kubectl -n $NS rollout status statefulset/kafka --timeout=300s

helm upgrade --install producer-api ./charts/api -n $NS --set image.tag="$API_TAG" --atomic
helm upgrade --install consumer-bot ./charts/bot -n $NS --set image.tag="$BOT_TAG" --atomic

kubectl -n $NS get pods
```

## Выкатка новой версии

Helm образы не качает: он только применяет манифест с новым тегом, а образ скачивает k3s на сервере.
Теги только конкретные (`v1.0.1`, хеш коммита), не `latest`, иначе откат не работает.
Имя образа в Docker Hub только в нижнем регистре.

```bash
# 1. собрать и запушить образ
docker build -t lccodder/kafka-template-producer:v1.0.1 ./producer
docker push lccodder/kafka-template-producer:v1.0.1

# 2. выкатить API
helm upgrade --install producer-api ./charts/api -n kafka-template --set image.tag=v1.0.1 --atomic

# то же для бота
docker build -t lccodder/kafka-template-consumer:v1.0.1 ./consumer
docker push lccodder/kafka-template-consumer:v1.0.1
helm upgrade --install consumer-bot ./charts/bot -n kafka-template --set image.tag=v1.0.1 --atomic
```

`--atomic` ждёт готовности подов (по умолчанию 5 минут) и при провале сам откатывает релиз.
Без `--set image.tag=...` деплой не запустится: тег обязателен.

Если репа в Docker Hub приватная:
```bash
kubectl -n kafka-template create secret docker-registry dockerhub \
  --docker-username=<логин> --docker-password=<токен>
```
и в `deployment.yaml` в `spec.template.spec` добавить:
```yaml
imagePullSecrets:
  - name: dockerhub
```

## Откат

```bash
helm history producer-api -n kafka-template                   # список ревизий
helm rollback producer-api -n kafka-template                  # на предыдущую
helm rollback producer-api 2 -n kafka-template                # на ревизию 2
helm get values producer-api -n kafka-template --revision 2   # какой тег был в ревизии 2
```

То же для бота: заменить `producer-api` на `consumer-bot`.
Тег образа возвращается вместе с ревизией, `--set` повторять не нужно.

## Обновление секретов и конфигов

```bash
# dockerhub креды
set -a; source .env; set +a
kubectl -n kafka-template create secret docker-registry dockerhub \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username="$DOCKERHUB_USER" \
  --docker-password="$DOCKERHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# пересоздать Secret из .env
kubectl -n kafka-template create secret generic app-secrets --from-env-file=.env \
  --dry-run=client -o yaml | kubectl apply -f -

# применить изменённый configmap.yaml
kubectl apply -f configmap.yaml

# поды сами новые значения не подхватят, нужен перезапуск
kubectl -n kafka-template rollout restart deployment/producer-api deployment/consumer-bot
kubectl -n kafka-template rollout restart statefulset/kafka
```

## Пересоздать БД с нуля (данные будут удалены)

`init.sql` MySQL выполняет только на пустом диске.

```bash
kubectl -n kafka-template delete statefulset mysql
kubectl -n kafka-template delete pvc data-mysql-0
kubectl -n kafka-template create configmap mysql-init --from-file=init.sql=scripts/init.sql \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f mysql/
```

## Проверка и отладка

```bash
kubectl -n kafka-template get pods
kubectl -n kafka-template get svc
kubectl -n kafka-template get pvc
helm list -n kafka-template

kubectl -n kafka-template logs deploy/producer-api
kubectl -n kafka-template logs deploy/consumer-bot
kubectl -n kafka-template logs statefulset/kafka
kubectl -n kafka-template logs statefulset/mysql

kubectl -n kafka-template describe pod <имя-пода>
kubectl -n kafka-template get events --sort-by=.lastTimestamp

# зайти в MySQL изнутри
kubectl -n kafka-template exec -it mysql-0 -- mysql -uroot -p
```

## Доступ снаружи

- API: Service `producer-api` типа NodePort на порту `30080`, nginx на хосте проксирует на `http://127.0.0.1:30080`.
- MySQL: Service `mysql-external`, NodePort `30306`.
- Kafka: наружу не выходит, только внутри кластера (`kafka:29092`).
- Порты NodePort должны входить в разрешённый пул лабы (по умолчанию в k3s: 30000-32767).

## Удаление

```bash
helm uninstall producer-api consumer-bot -n kafka-template

# снести всё, включая диски MySQL и Kafka (данные пропадут)
kubectl delete namespace kafka-template
```

