# mongo-sharding — Задание 2 (Шардирование)

Шардированный кластер MongoDB с двумя шардами и приложением `pymongo-api`.

## Состав стенда

| Сервис          | Тип                       | Порт  |
|-----------------|---------------------------|-------|
| `config_srv`    | Config Server (replica set `config_server`) | 27017 |
| `shard_1`       | Shard (replica set `shard_1`)               | 27018 |
| `shard_2`       | Shard (replica set `shard_2`)               | 27019 |
| `mongos_router` | Маршрутизатор запросов (mongos)             | 27020 |
| `pymongo_api`   | Приложение (FastAPI), образ `kazhem/pymongo_api:1.0.0` | 8080 |

Приложение подключается **только к `mongos_router`** — он распределяет данные между шардами.

## Как запустить

1. Поднять контейнеры:

   ```shell
   docker compose up -d
   ```

2. Инициализировать кластер и наполнить базу (1000 документов):

   ```shell
   chmod +x scripts/mongo-init.sh
   ./scripts/mongo-init.sh
   ```

   Скрипт по шагам:
   1. инициирует config server (`rs.initiate` с `configsvr: true`);
   2. инициирует replica set каждого шарда (`shard_1`, `shard_2`);
   3. регистрирует шарды на роутере через `sh.addShard(...)`;
   4. включает шардирование БД `somedb`, создаёт hashed-индекс по полю `name`
      и шардирует коллекцию `helloDoc`;
   5. вставляет 1000 документов и печатает количество документов в каждом шарде.

## Как проверить

Откройте в браузере <http://localhost:8080/> — приложение вернёт JSON со статусом
кластера. Документация API: <http://localhost:8080/docs>.

Общее количество документов через роутер:

```shell
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
db = db.getSiblingDB("somedb")
db.helloDoc.countDocuments()
EOF
```

Количество документов в каждом шарде (сумма ≈ 1000, данные распределены):

```shell
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<EOF
db = db.getSiblingDB("somedb")
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard_2 mongosh --port 27019 --quiet <<EOF
db = db.getSiblingDB("somedb")
db.helloDoc.countDocuments()
EOF
```

## Остановить и очистить

```shell
docker compose down -v
```
