FROM python:3.11.9-slim AS builder

WORKDIR /build
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


FROM python:3.11.9-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN useradd --no-create-home --shell /bin/false appuser

WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ .

USER appuser

EXPOSE 8000
CMD ["gunicorn", "bank.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "4", "--timeout", "30"]
