# sharding-repl-cache — Задание 4 (Шардирование + Репликация + Кеширование)

Финальная конфигурация: шардированный кластер MongoDB с репликацией каждого шарда
**плюс кеширование запросов приложения через Redis**.

Это итоговая директория проекта — она включает решения заданий 2, 3 и 4.

## Состав стенда

| Сервис          | Тип                                         | Порт  |
|-----------------|---------------------------------------------|-------|
| `config_srv`    | Config Server (replica set `config_server`) | 27017 |
| `shard_1_1/2/3` | Shard 1 — replica set `shard_1_replicaset`  | 27018–27020 |
| `shard_2_1/2/3` | Shard 2 — replica set `shard_2_replicaset`  | 27021–27023 |
| `mongos_router` | Маршрутизатор запросов (mongos)             | 27024 |
| `redis`         | Кеш (Redis)                                 | 6379  |
| `pymongo_api`   | Приложение, образ `kazhem/pymongo_api:1.0.0`| 8080  |

Кеширование включается переменной окружения приложения
`REDIS_URL: "redis://redis:6379"`. Закешированы ответы эндпоинта
`/<collection_name>/users`.

## Как запустить

1. Поднять контейнеры:

   ```shell
   docker compose up -d
   ```

2. Инициализировать кластер и наполнить базу:

   ```shell
   chmod +x scripts/mongo-init.sh
   ./scripts/mongo-init.sh
   ```

   Шаги инициализации те же, что в `mongo-sharding-repl` (config server →
   два шарда по 3 реплики → регистрация шардов на роутере → шардирование
   `somedb.helloDoc` и вставка 1000 документов).

## Как проверить

### Информация о кластере и кеше

Откройте <http://localhost:8080/> — в JSON будет `mongo_topology_type: "Sharded"`,
список шардов, статус реплик и поле `cache_enabled: true`.

### Скорость кеширования (главная проверка задания 4)

Эндпоинт `/<collection_name>/users` искусственно «тормозит» на 1 секунду при
обращении к БД, но результат кешируется в Redis на 60 секунд.

```shell
# Первый запрос — идёт в MongoDB, ~1 секунда:
time curl -s http://localhost:8080/helloDoc/users -o /dev/null

# Повторный запрос — отдаётся из кеша Redis, <100 мс:
time curl -s http://localhost:8080/helloDoc/users -o /dev/null
```

Проверить, что в Redis появились ключи кеша:

```shell
docker compose exec -T redis redis-cli KEYS '*'
```

### Количество документов в шардах и реплик

```shell
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
db = db.getSiblingDB("somedb")
db.helloDoc.countDocuments()
rs.status().members.length
EOF
```

## Остановить и очистить

```shell
docker compose down -v
```
