FROM python:3-slim

WORKDIR /app

COPY n9e /app/n9e
COPY etc /app/etc/
COPY integrations /app/integrations/

RUN pip install --no-cache-dir requests Jinja2

EXPOSE 17000 20090

CMD ["/app/n9e"]