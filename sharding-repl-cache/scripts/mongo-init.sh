#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB с репликацией и кешированием.
# Каждый шард — replica set из трёх узлов.
# Запускать из директории sharding-repl-cache после `docker compose up -d`.
# Скрипт идемпотентен: повторный запуск ничего не ломает.
###

# Ждём, пока mongod/mongos начнёт отвечать на ping (до 60 секунд)
wait_for_mongo() {
  local svc=$1 port=$2
  for i in $(seq 1 30); do
    if docker compose exec -T "$svc" mongosh --port "$port" --quiet \
        --eval "db.adminCommand('ping').ok" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "!!! $svc:$port не отвечает на ping за 60 секунд" >&2
  exit 1
}

# Ждём, пока в replica set появится PRIMARY (до 60 секунд)
wait_for_primary() {
  local svc=$1 port=$2
  for i in $(seq 1 30); do
    if docker compose exec -T "$svc" mongosh --port "$port" --quiet \
        --eval "try { rs.status().members.some(m => m.stateStr === 'PRIMARY') } catch (e) { false }" \
        2>/dev/null | grep -q true; then
      return 0
    fi
    sleep 2
  done
  echo "!!! $svc:$port — PRIMARY не выбран за 60 секунд" >&2
  exit 1
}

echo ">>> 1. Инициализируем config server (replica set 'config_server')"
wait_for_mongo config_srv 27017
docker compose exec -T config_srv mongosh --port 27017 --quiet <<'EOF'
try {
  rs.status();
  print("config server уже инициализирован — пропускаем");
} catch (e) {
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [{ _id: 0, host: "config_srv:27017" }]
  });
}
EOF
wait_for_primary config_srv 27017

echo ">>> 2. Инициализируем shard_1 (3 реплики: shard_1_1 / shard_1_2 / shard_1_3)"
wait_for_mongo shard_1_1 27018
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<'EOF'
try {
  rs.status();
  print("shard_1_replicaset уже инициализирован — пропускаем");
} catch (e) {
  rs.initiate({
    _id: "shard_1_replicaset",
    members: [
      { _id: 0, host: "shard_1_1:27018" },
      { _id: 1, host: "shard_1_2:27019" },
      { _id: 2, host: "shard_1_3:27020" }
    ]
  });
}
EOF
wait_for_primary shard_1_1 27018

echo ">>> 3. Инициализируем shard_2 (3 реплики: shard_2_1 / shard_2_2 / shard_2_3)"
wait_for_mongo shard_2_1 27021
docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<'EOF'
try {
  rs.status();
  print("shard_2_replicaset уже инициализирован — пропускаем");
} catch (e) {
  rs.initiate({
    _id: "shard_2_replicaset",
    members: [
      { _id: 0, host: "shard_2_1:27021" },
      { _id: 1, host: "shard_2_2:27022" },
      { _id: 2, host: "shard_2_3:27023" }
    ]
  });
}
EOF
wait_for_primary shard_2_1 27021

echo ">>> 4. Регистрируем шарды (каждый — replica set) на mongos-роутере"
wait_for_mongo mongos_router 27024
docker compose exec -T mongos_router mongosh --port 27024 --quiet <<'EOF'
const registered = db.adminCommand({ listShards: 1 }).shards.map(s => s._id);
if (!registered.includes("shard_1_replicaset")) {
  sh.addShard("shard_1_replicaset/shard_1_1:27018,shard_1_2:27019,shard_1_3:27020");
} else {
  print("shard_1_replicaset уже зарегистрирован — пропускаем");
}
if (!registered.includes("shard_2_replicaset")) {
  sh.addShard("shard_2_replicaset/shard_2_1:27021,shard_2_2:27022,shard_2_3:27023");
} else {
  print("shard_2_replicaset уже зарегистрирован — пропускаем");
}
EOF

echo ">>> 5. Включаем шардирование somedb и наполняем коллекцию helloDoc"
docker compose exec -T mongos_router mongosh --port 27024 --quiet <<'EOF'
sh.enableSharding("somedb");
db = db.getSiblingDB("somedb");
db.helloDoc.createIndex({ name: "hashed" });
try {
  sh.shardCollection("somedb.helloDoc", { name: "hashed" });
} catch (e) {
  print("коллекция уже шардирована — пропускаем: " + e.codeName);
}

if (db.helloDoc.countDocuments() === 0) {
  const docs = [];
  for (let i = 0; i < 1000; i++) {
    docs.push({ age: i, name: "ly" + i });
  }
  const res = db.helloDoc.insertMany(docs);
  print("Вставлено документов: " + Object.keys(res.insertedIds).length);
} else {
  print("данные уже загружены — пропускаем вставку");
}

print("Всего документов через mongos: " + db.helloDoc.countDocuments());
EOF

echo ">>> 6. Количество документов в shard_1 (узел shard_1_1)"
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<'EOF'
db.getMongo().setReadPref("primaryPreferred");
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> 7. Количество документов в shard_2 (узел shard_2_1)"
docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<'EOF'
db.getMongo().setReadPref("primaryPreferred");
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> 8. Статус реплик shard_1 (members)"
docker compose exec -T shard_1_1 mongosh --port 27018 --quiet <<'EOF'
rs.status().members.forEach(m => print(m.name + " => " + m.stateStr));
EOF

echo ">>> 9. Статус реплик shard_2 (members)"
docker compose exec -T shard_2_1 mongosh --port 27021 --quiet <<'EOF'
rs.status().members.forEach(m => print(m.name + " => " + m.stateStr));
EOF

echo ">>> Готово. Проверьте приложение: http://localhost:8080/"
