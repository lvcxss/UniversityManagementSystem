#!/bin/bash
# import-backup [new database] [user]

# ================= WARNING ================= #
#      THIS DROPS THE EXISTING DATABASE
# =========================================== #

database="$1"
user="$2"

[[ -z "$database" ]] && database="projetoimported"
[[ -z "$user" ]] && user="postgres"
echo "New Database: $database"
echo "User: $user"

# psql -U "$user" -d "postgres" -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE datname = '$database';"
psql -U "$user" -d "postgres" -c "DROP DATABASE IF EXISTS $database;"
psql -U "$user" -d "postgres" -c "CREATE DATABASE $database;"
psql -U "$user" -d "$database" -f backup.sql
exit 0
