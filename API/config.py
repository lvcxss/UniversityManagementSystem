import os


class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "default secret")
    DB_USER = os.environ.get("DB_USER", "user")
    DB_PASSWORD = os.environ.get("DB_PASSWORD", "password")
    DB_PORT = os.environ.get("DB_PORT", "0000")
    DB_NAME = os.environ.get("DB_NAME", "dbname")
    DB_HOST = os.environ.get("DB_HOST", "localhost")
