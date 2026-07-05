#!/bin/bash
set -e

###
# Инициализация шардированного кластера MongoDB и наполнение данными.
# Запускать из директории mongo-sharding после `docker compose up -d`.
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

echo ">>> 2. Инициализируем shard_1 (replica set 'shard_1')"
wait_for_mongo shard_1 27018
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<'EOF'
try {
  rs.status();
  print("shard_1 уже инициализирован — пропускаем");
} catch (e) {
  rs.initiate({
    _id: "shard_1",
    members: [{ _id: 0, host: "shard_1:27018" }]
  });
}
EOF
wait_for_primary shard_1 27018

echo ">>> 3. Инициализируем shard_2 (replica set 'shard_2')"
wait_for_mongo shard_2 27019
docker compose exec -T shard_2 mongosh --port 27019 --quiet <<'EOF'
try {
  rs.status();
  print("shard_2 уже инициализирован — пропускаем");
} catch (e) {
  rs.initiate({
    _id: "shard_2",
    members: [{ _id: 0, host: "shard_2:27019" }]
  });
}
EOF
wait_for_primary shard_2 27019

echo ">>> 4. Регистрируем шарды на mongos-роутере"
wait_for_mongo mongos_router 27020
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
const registered = db.adminCommand({ listShards: 1 }).shards.map(s => s._id);
if (!registered.includes("shard_1")) {
  sh.addShard("shard_1/shard_1:27018");
} else {
  print("shard_1 уже зарегистрирован — пропускаем");
}
if (!registered.includes("shard_2")) {
  sh.addShard("shard_2/shard_2:27019");
} else {
  print("shard_2 уже зарегистрирован — пропускаем");
}
EOF

echo ">>> 5. Включаем шардирование БД somedb и наполняем коллекцию helloDoc"
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
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

echo ">>> 6. Количество документов в shard_1"
docker compose exec -T shard_1 mongosh --port 27018 --quiet <<'EOF'
db.getMongo().setReadPref("primaryPreferred");
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> 7. Количество документов в shard_2"
docker compose exec -T shard_2 mongosh --port 27019 --quiet <<'EOF'
db.getMongo().setReadPref("primaryPreferred");
db = db.getSiblingDB("somedb");
print(db.helloDoc.countDocuments());
EOF

echo ">>> Готово. Проверьте приложение: http://localhost:8080/"
