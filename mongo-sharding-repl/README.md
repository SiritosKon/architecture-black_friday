# mongo-sharding-repl — Задание 3 (Шардирование + Репликация)

Шардированный кластер MongoDB, где **каждый шард — это replica set из трёх узлов**.
Репликация повышает отказоустойчивость: при отказе одного узла шарда данные
остаются доступны на оставшихся репликах.

## Состав стенда

| Сервис          | Тип                                         | Порт  |
|-----------------|---------------------------------------------|-------|
| `config_srv`    | Config Server (replica set `config_server`) | 27017 |
| `shard_1_1`     | Shard 1, реплика 1 (`shard_1_replicaset`)   | 27018 |
| `shard_1_2`     | Shard 1, реплика 2 (`shard_1_replicaset`)   | 27019 |
| `shard_1_3`     | Shard 1, реплика 3 (`shard_1_replicaset`)   | 27020 |
| `shard_2_1`     | Shard 2, реплика 1 (`shard_2_replicaset`)   | 27021 |
| `shard_2_2`     | Shard 2, реплика 2 (`shard_2_replicaset`)   | 27022 |
| `shard_2_3`     | Shard 2, реплика 3 (`shard_2_replicaset`)   | 27023 |
| `mongos_router` | Маршрутизатор запросов (mongos)             | 27024 |
| `pymongo_api`   | Приложение, образ `kazhem/pymongo_api:1.0.0`| 8080  |

Группы репликации:
- **shard_1_replicaset** = `shard_1_1` + `shard_1_2` + `shard_1_3`
- **shard_2_replicaset** = `shard_2_1` + `shard_2_2` + `shard_2_3`

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

   Скрипт по шагам:
   1. инициирует config server;
   2. инициирует replica set первого шарда из трёх узлов (`rs.initiate` с тремя `members`);
   3. инициирует replica set второго шарда из трёх узлов;
   4. регистрирует шарды на роутере, передавая полный список узлов каждого
      replica set: `sh.addShard("shard_1_replicaset/shard_1_1:27018,shard_1_2:27019,shard_1_3:27020")`;
   5. включает шардирование БД `somedb`, шардирует коллекцию `helloDoc` по hashed-индексу
      и вставляет 1000 документов;
   6–9. печатает количество документов в каждом шарде и статус реплик (`rs.status`).

## Как проверить

Откройте <http://localhost:8080/> — в JSON будет `mongo_topology_type: "Sharded"`,
список шардов и информация о репликации.

Количество реплик в шарде (должно быть 3):

```shell
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
db = db.getSiblingDB("somedb")
rs.status().members.length
EOF
```

Статус каждого узла replica set (один PRIMARY + два SECONDARY):

```shell
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " => " + m.stateStr))
EOF
```

Количество документов в шардах (сумма ≈ 1000):

```shell
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
db = db.getSiblingDB("somedb")
db.helloDoc.countDocuments()
EOF

docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<EOF
db = db.getSiblingDB("somedb")
db.helloDoc.countDocuments()
EOF
```

## Остановить и очистить

```shell
docker compose down -v
```
