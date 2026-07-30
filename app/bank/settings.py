import os
import dj_database_url

SECRET_KEY = os.environ["SECRET_KEY"]
DEBUG = os.environ.get("DEBUG", "false").lower() == "true"
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "*").split(",")

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "django_prometheus",
    "api",
]

MIDDLEWARE = [
    "django_prometheus.middleware.PrometheusBeforeMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django_prometheus.middleware.PrometheusAfterMiddleware",
]

ROOT_URLCONF = "bank.urls"
WSGI_APPLICATION = "bank.wsgi.application"

DATABASE_URL = os.environ["DATABASE_URL"]
DATABASES = {
    "default": dj_database_url.parse(DATABASE_URL, conn_max_age=60)
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
