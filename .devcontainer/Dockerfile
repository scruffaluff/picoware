FROM docker.io/debian:13-slim

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages.
RUN apt-get update --ignore-missing && apt-get install --no-install-recommends \
  --quiet --yes ca-certificates curl gcc git sudo tar zip && rm --force \
  --recursive /var/lib/apt/lists/*

# Create non-priviledged user and grant user passwordless sudo.
RUN useradd --create-home --no-log-init debian \
    && usermod --append --groups sudo debian \
    && printf "debian ALL=(ALL) NOPASSWD:ALL\n" >> /etc/sudoers

ENV HOME=/home/debian USER=debian
USER debian

# Disable Git dubious ownership warnings.
RUN git config --global --add safe.directory '*'
