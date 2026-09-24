# syntax=docker/dockerfile:1
FROM public.ecr.aws/lts/ubuntu:24.04

ARG TARGETARCH
ARG github_apt_repo=https://cli.github.com/packages
ARG keyrings_dir=/usr/share/keyrings
ARG kubernetes_version=v1.36
ARG yq_package_url=https://github.com/mikefarah/yq/releases/latest/download
ARG awscli_install_dir=/opt

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR $keyrings_dir

# hadolint ignore=DL3008
RUN --mount=type=secret,id=zscaler_ca,target=/tmp/zscaler.crt,required=false \
    mkdir -p /etc/ssl/certs /usr/local/share/ca-certificates /etc/apt/keyrings && \
    touch /etc/ssl/certs/ca-certificates.crt && \
    if [ -f /tmp/zscaler.crt ]; then \
        cp /tmp/zscaler.crt /usr/local/share/ca-certificates/zscaler.crt && \
        cat /tmp/zscaler.crt >> /etc/ssl/certs/ca-certificates.crt ; \
    fi && \
    apt-get update -qq && \
    apt-get install -qy --no-install-recommends ca-certificates curl gnupg && \
    update-ca-certificates && \
    curl -fsSL "${github_apt_repo}/githubcli-archive-keyring.gpg" -o github.gpg && \
    curl -fsSL "https://pgp.mongodb.com/server-7.0.pub" -o mongodb.gpg && \
    curl -fsSL "https://www.postgresql.org/media/keys/ACCC4CF8.asc" -o apt.postgresql.org.asc && \
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${kubernetes_version}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    chmod 644 github.gpg mongodb.gpg apt.postgresql.org.asc /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [arch=${TARGETARCH} signed-by=${keyrings_dir}/github.gpg] ${github_apt_repo} stable main" > /etc/apt/sources.list.d/github.list && \
    echo "deb [arch=${TARGETARCH} signed-by=${keyrings_dir}/mongodb.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb.list && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${kubernetes_version}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update -qq && \
    apt-get install -qy --no-install-recommends \
        dnsutils file gh git jq libarchive-tools make mysql-client netcat-openbsd \
        postgresql-common pv wget2 gettext mongodb-mongosh=2.2.10 \
        mongodb-database-tools=100.9.4 redis-tools kubectl && \
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
    apt-get install -qy --no-install-recommends postgresql-client-18 && \
    rm -fr /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /tmp
RUN yq_binary="yq_linux_${TARGETARCH}" && \
    curl -fsSL "${yq_package_url}/${yq_binary}.tar.gz" | tar -xzf - && \
    cp "${yq_binary}" /usr/bin/yq && \
    curl -Ssf "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" \
        | bsdtar -C "${awscli_install_dir}" -xf - \
          --exclude 'aws_completer' --exclude 'docutils' --exclude 'examples' \
          --exclude 'install' --exclude 'topics' && \
    chmod +x "${awscli_install_dir}/aws/dist/aws" && \
    rm -fr /tmp/* /var/tmp/*

ARG go_version=1.26.5
RUN curl -fsSL "https://go.dev/dl/go${go_version}.linux-${TARGETARCH}.tar.gz" \
        | tar -xzf - && \
    cp -r go /usr/local && \
    rm -fr /tmp/*

ENV PATH=$PATH:/usr/local/go/bin:$awscli_install_dir/aws/dist

COPY --from=peakcom/s5cmd:v2.3.0 s5cmd /bin/s5cmd

RUN groupadd -g 1001 user && \
    useradd -mu 1001 -g user user

WORKDIR /home/user
USER user

# Crude smoke test.
RUN aws --version ; \
    gh --version ; \
    go version ; \
    jq --version ; \
    make --version ; \
    echo -n "mongosh "; mongosh --version ; \
    mongodump --version ; \
    mysql --version ; \
    psql --version ; \
    pg_dump --version ; \
    createdb --version ; \
    dropdb --version ; \
    redis-cli --version ; \
    echo -n "s5cmd "; s5cmd version ; \
    yq --version ; \
    kubectl version --client ; \
    dig -v ; \
    host -V

CMD ["/bin/bash"]
LABEL org.opencontainers.image.source=https://github.com/alphagov/govuk-infrastructure/tree/main/images/toolbox/
