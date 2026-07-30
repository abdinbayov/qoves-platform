from django.urls import path, include

urlpatterns = [
    path("", include("api.urls")),
    path("", include("django_prometheus.urls")),
]
