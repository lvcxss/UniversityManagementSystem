param(
    [string]$database,
    [string]$user
)

if (-not $database) { $database = "projeto" }
if (-not $user) { $user = "postgres" }

Write-Host "Database: $database"
Write-Host "User: $user"

pg_dump -h localhost -p 5432 -U $user -d $database -f backup.sql

exit 0
