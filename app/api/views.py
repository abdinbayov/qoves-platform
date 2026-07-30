from django.http import JsonResponse, HttpResponse
from django.db import connection


def hello(request):
    return JsonResponse({"message": "hello from qoves banking api"})


def healthz(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return JsonResponse({"status": "ok"}, status=200)
    except Exception as exc:
        return JsonResponse({"status": "error", "detail": str(exc)}, status=503)
