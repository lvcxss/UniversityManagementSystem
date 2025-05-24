#!/bin/bash
# import.sh [database] [user]
# vou assumir q todos usamos db projeto e utilizador postgres
# mas se nao for o caso podem passar como argumento

database="$1"
user="$2"

[[ -z "$database" ]] && database="projeto"
[[ -z "$user" ]] && user="postgres"
echo "Database: $database"
echo "User: $user"

for file in scripts/*.sql; do
  psql -h localhost -p 5432 -d "$database" -U "$user" -q -f "$file"
done

exit 0
