#!/bin/bash
# export.sh [database] [user]
# vou assumir q todos usamos db projeto e utilizador postgres
# mas se nao for o caso podem passar como argumento

database="$1"
user="$2"

[[ -z "$database" ]] && database="projeto"
[[ -z "$user" ]] && user="postgres"
echo "Database: $database"
echo "User: $user"

pg_dump -h localhost -p 5432 -U "$user" -d "$database" -f backup.sql

exit 0
