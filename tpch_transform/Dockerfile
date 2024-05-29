FROM mcr.microsoft.com/azure-cli as base

RUN apk add --no-cache unixodbc-dev g++ curl \
  && pip install -q --upgrade pip setuptools wheel \
  && pip install -q --no-cache-dir dbt-core \
  && pip install -q --no-cache-dir dbt-snowflake

COPY . /usr/app/tpch_transform

WORKDIR /usr/app/tpch_transform

ENV PYTHONUNBUFFERED=1

RUN chmod 700 /usr/app/tpch_transform/entrypoint.sh 

ENTRYPOINT ["/usr/app/tpch_transform/entrypoint.sh"]
