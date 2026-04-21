FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# jq is the only extra apt package needed beyond the base image
RUN apt-get update && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*
