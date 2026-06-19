#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB и наполнение данными.
# Запускать из директории mongo-sharding после `docker compose up -d`.
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

echo ">>> 2. Инициализируем shard_1 (replica set 'shard_1')"
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard_1",
  members: [{ _id: 0, host: "shard_1:27018" }]
});
EOF
sleep 5

echo ">>> 3. Инициализируем shard_2 (replica set 'shard_2')"
docker compose exec -T shard_2 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "shard_2",
  members: [{ _id: 0, host: "shard_2:27019" }]
});
EOF
sleep 5

echo ">>> 4. Регистрируем шарды на mongos-роутере"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard_1/shard_1:27018");
sh.addShard("shard_2/shard_2:27019");
EOF
sleep 3

echo ">>> 5. Включаем шардирование БД somedb и наполняем коллекцию helloDoc"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
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

echo ">>> 6. Количество документов в shard_1"
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<EOF
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> 7. Количество документов в shard_2"
docker compose exec -T shard_2 mongosh --port 27019 --quiet <<EOF
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> Готово. Проверьте приложение: http://localhost:8080/"
