#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB с репликацией.
# Каждый шард — replica set из трёх узлов.
# Запускать из директории mongo-sharding-repl после `docker compose up -d`.
###

echo ">>> 1. Инициализируем config server (replica set 'config_server')"
docker compose exec -T config_srv mongosh --port 27017 --quiet <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [{ _id: 0, host: "config_srv:27017" }]
});
EOF
sleep 5

echo ">>> 2. Инициализируем shard_1 (3 реплики: shard_1_1 / shard_1_2 / shard_1_3)"
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard_1_replicaset",
  members: [
    { _id: 0, host: "shard_1_1:27018" },
    { _id: 1, host: "shard_1_2:27019" },
    { _id: 2, host: "shard_1_3:27020" }
  ]
});
EOF
sleep 5

echo ">>> 3. Инициализируем shard_2 (3 реплики: shard_2_1 / shard_2_2 / shard_2_3)"
docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<EOF
rs.initiate({
  _id: "shard_2_replicaset",
  members: [
    { _id: 0, host: "shard_2_1:27021" },
    { _id: 1, host: "shard_2_2:27022" },
    { _id: 2, host: "shard_2_3:27023" }
  ]
});
EOF
sleep 10

echo ">>> 4. Регистрируем шарды (каждый — replica set) на mongos-роутере"
docker compose exec -T mongos_router mongosh --port 27024 --quiet <<EOF
sh.addShard("shard_1_replicaset/shard_1_1:27018,shard_1_2:27019,shard_1_3:27020");
sh.addShard("shard_2_replicaset/shard_2_1:27021,shard_2_2:27022,shard_2_3:27023");
EOF
sleep 3

echo ">>> 5. Включаем шардирование somedb и наполняем коллекцию helloDoc"
docker compose exec -T mongos_router mongosh --port 27024 --quiet <<EOF
sh.enableSharding("somedb");
db = db.getSiblingDB("somedb");
db.helloDoc.createIndex({ name: "hashed" });
sh.shardCollection("somedb.helloDoc", { name: "hashed" });

for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}

print("Всего документов через mongos: " + db.helloDoc.countDocuments());
EOF
sleep 3

echo ">>> 6. Количество документов в первичном узле shard_1"
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> 7. Количество документов в первичном узле shard_2"
docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<EOF
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> 8. Статус реплик shard_1 (members)"
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " => " + m.stateStr));
EOF

echo ">>> 9. Статус реплик shard_2 (members)"
docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<EOF
rs.status().members.forEach(m => print(m.name + " => " + m.stateStr));
EOF

echo ">>> Готово. Проверьте приложение: http://localhost:8080/"
