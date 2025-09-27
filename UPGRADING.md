## Postgres

### Backup Old Data
```shell
cp -r ./data/db_data ./data/db_data_16.4
```

### Dump Old Data
```shell
docker run --rm -v ./data/db_data:/var/lib/postgresql/data -e POSTGRES_USER=foxtrove -e POSTGRES_DB=foxtrove_development -e POSTGRES_HOST_AUTH_METHOD=trust -d --name foxtrove_pg16.4 postgres:16.4-alpine3.20
docker exec foxtrove_pg16.4 pg_dumpall -U foxtrove > ./pg16.4_dump.sql
docker rm -f foxtrove_pg16.4
```

### Import Old Data
```shell
docker run --rm -v ./data/db_data_17.6:/var/lib/postgresql/data -e POSTGRES_USER=foxtrove -e POSTGRES_DB=foxtrove_development -e POSTGRES_HOST_AUTH_METHOD=trust -d --name foxtrove_pg17.6 postgres:17.6-alpine3.20
cat pg16.4_dump.sql | docker exec -i foxtrove_pg17.6 psql -U foxtrove -d postgres
docker rm -f foxtrove_pg17.6
```

### Replace Old Data
```shell
rm -rf ./data/db_data
mv ./data/db_data_17.6 ./data/db_data
```

### Remove Backup Data
```shell
rm -rf ./data/db_data_16.4
```
