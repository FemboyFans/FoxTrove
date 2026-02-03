## Postgres

### Backup Old Data
```shell
cp -r ./data/db_data ./data/db_data_17.6
```

### Dump Old Data
```shell
docker run --rm -v ./data/db_data:/var/lib/postgresql/data -e POSTGRES_USER=foxtrove -e POSTGRES_DB=foxtrove_development -e POSTGRES_HOST_AUTH_METHOD=trust -e PGDATA=/var/lib/postgresql/data -d --name foxtrove_pg17.6 postgres:17.6-alpine
docker exec foxtrove_pg17.6 pg_dumpall -U foxtrove > ./pg17.6_dump.sql
docker rm -f foxtrove_pg17.6
```

### Import Old Data
```shell
docker run --rm -v ./data/db_data_18.1:/var/lib/postgresql/data -e POSTGRES_USER=foxtrove -e POSTGRES_DB=foxtrove_development -e POSTGRES_HOST_AUTH_METHOD=trust -e PGDATA=/var/lib/postgresql/data -d --name foxtrove_pg18.1 postgres:18.1-alpine
docker exec -i foxtrove_pg18.1 psql -U foxtrove -d postgres < pg17.6_dump.sql
docker rm -f foxtrove_pg18.1
```

### Replace Old Data
```shell
rm -rf ./data/db_data
mv ./data/db_data_18.1 ./data/db_data
```

### Remove Backup Data
```shell
rm -rf ./data/db_data_17.6
rm pg17.6_dump.sql
```
