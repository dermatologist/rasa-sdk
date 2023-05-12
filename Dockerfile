FROM python:3.10-alpine as base

# hadolint ignore=DL3005,DL3008
RUN apk upgrade --no-cache && \
    apk add --no-cache bash libstdc++ openblas

FROM base as python_builder

RUN apk add --no-cache curl gcc g++ gfortran pkgconfig cmake make musl-dev openblas-dev

# install poetry
# keep this in sync with the version in pyproject.toml and Dockerfile
ENV POETRY_VERSION 1.4.2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -sSL https://install.python-poetry.org | python
ENV PATH "/root/.local/bin:/opt/venv/bin:${PATH}"

# install dependencies
COPY . /app/

WORKDIR /app

# hadolint ignore=SC1091,DL3013
RUN python -m venv /opt/venv && \
  . /opt/venv/bin/activate && \
  pip install --no-cache-dir -U pip && \
  pip install --no-cache-dir wheel && \
  poetry install --only main --no-root --no-interaction

# install dependencies and build wheels
# hadolint ignore=SC1091,DL3013
RUN . /opt/venv/bin/activate && poetry build -f wheel -n \
  && pip install --no-cache-dir --no-deps dist/*.whl \
  && mkdir /wheels \
  && poetry export -f requirements.txt --without-hashes --output /wheels/requirements.txt \
  && poetry run pip wheel --wheel-dir=/wheels -r /wheels/requirements.txt \
  && find /app/dist -maxdepth 1 -mindepth 1 -name '*.whl' -print0 | xargs -0 -I {} mv {} /wheels/

WORKDIR /wheels
# install wheels
# hadolint ignore=SC1091,DL3013
RUN find . -name '*.whl' -maxdepth 1 -exec basename {} \; | awk -F - '{ gsub("_", "-", $1); print $1 }' | uniq > /wheels/requirements.txt \
  && rm -rf /opt/venv \
  && python -m venv /opt/venv \
  && . /opt/venv/bin/activate \
  && pip install --no-cache-dir -U pip \
  && pip install --no-cache-dir --no-index --find-links=/wheels -r /wheels/requirements.txt \
  && pip install farm-haystack -f https://download.pytorch.org/whl/cpu/torch-1.13.0%2Bcpu-cp310-cp310-linux_x86_64.whl \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
  && rm -rf /wheels \
  && rm -rf /root/.cache/pip/*

# final image
FROM base

# copy needed files
COPY ./entrypoint.sh /app/
COPY --from=python_builder /opt/venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

# update permissions & change user
RUN chgrp -R 0 /app && chmod -R g=u /app
USER 1001

# change shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# create a mount point for custom actions and the entry point
WORKDIR /app
EXPOSE 5055
ENTRYPOINT ["./entrypoint.sh"]
CMD ["start", "--actions", "actions"]
