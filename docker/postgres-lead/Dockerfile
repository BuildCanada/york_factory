# Development/test only. Production uses PlanetScale's TIN implementation.
FROM postgis/postgis:18-3.6 AS build

ARG LEAD_REVISION=bd95c7e51b6afce81396790852ee2f2c169570ad
ENV PGRX_HOME=/opt/pgrx
ENV PATH=/root/.cargo/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates clang curl git libclang-dev libssl-dev \
    pkg-config postgresql-server-dev-18 \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain 1.96.0
RUN cargo install cargo-pgrx --version 0.19.1 --locked
RUN cargo pgrx init --pg18=/usr/lib/postgresql/18/bin/pg_config
RUN git init /opt/lead && cd /opt/lead \
    && git remote add origin https://github.com/planetscale/lead.git \
    && git fetch --depth 1 origin "$LEAD_REVISION" \
    && git checkout --detach FETCH_HEAD
WORKDIR /opt/lead
RUN cargo pgrx package --package tin --no-default-features --features pg18 \
    --pg-config /usr/lib/postgresql/18/bin/pg_config --out-dir /opt/extension

FROM postgis/postgis:18-3.6
COPY --from=build /opt/extension/ /
