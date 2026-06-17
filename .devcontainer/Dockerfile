FROM docker.io/debian:13-slim

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

# Install essential packages.
RUN apt-get update --ignore-missing && apt-get install --quiet --yes \
  gcc curl git sudo tar zip

# Create non-priviledged user and grant user passwordless sudo.
RUN useradd --create-home --no-log-init debian \
    && usermod --append --groups sudo debian \
    && printf "debian ALL=(ALL) NOPASSWD:ALL\n" >> /etc/sudoers

ENV HOME=/home/debian USER=debian
USER debian

# Disable Git dubious ownership warnings.
RUN git config --global --add safe.directory '*'
