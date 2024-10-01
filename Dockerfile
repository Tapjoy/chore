################################################################################
# Ruby Image
################################################################################

ARG ROOT_IMAGE
FROM ${ROOT_IMAGE} as ruby_image

# Install base tooling and library requirements
ENV DEBIAN_FRONTEND=noninteractive \
    GPG_SERVERS='keyserver.ubuntu.com hkp://keyserver.ubuntu.com:80 pgp.mit.edu'
RUN apt-get update -q &&\
    apt-get upgrade -yq --no-install-recommends &&\
    apt-get install -yq --no-install-recommends ca-certificates curl git jq less unzip vim &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install RVM
RUN curl -sSL https://get.rvm.io >/tmp/rvm-install.sh &&\
    test "$(cat /tmp/rvm-install.sh)" &&\
    bash /tmp/rvm-install.sh stable &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install Ruby
# Switch to a login shell so we can invoke rvm
SHELL [ "/bin/bash", "-l", "-c" ]

ADD ["Gemfile.lock", "/tmp/"]
RUN test "$(grep -A 1 'RUBY VERSION' /tmp/Gemfile.lock)" &&\
    ruby_version="$(grep -A 1 'RUBY VERSION' /tmp/Gemfile.lock | tail -n 1 | sed 's/ruby//' | awk '{$1=$1};1' | grep -oE '^[0-9\.]+')" &&\
    rvm install "${ruby_version}" &&\
    rvm use "${ruby_version}" --default &&\
    ruby -v

################################################################################
# Base Image
################################################################################

FROM ruby_image as baseimage

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 \
    APP_ROOT=/project APP_USER=webuser APP_USER_UID=1001

# Install OS-level language locales
RUN apt-get update -q &&\
    apt-get install -y --no-install-recommends locales &&\
    locale-gen $LANG && update-locale LANG=$LANG &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

# If a bundler version is specified in the Gemfile.lock, use it, otherwise install the latest 1.x
# Also install foreman system-wide
ADD ["Gemfile.lock", "/tmp/"]
RUN test "$(grep -A 1 'BUNDLED WITH' /tmp/Gemfile.lock)" &&\
    gem install bundler --no-document --version "$(grep -A 1 'BUNDLED WITH' /tmp/Gemfile.lock | tail -n 1)" ||\
    gem install -N bundler --version '~> 1.0' &&\
    gem install -N foreman &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

RUN mkdir -p ${APP_ROOT} &&\
    git config --global --add safe.directory ${APP_ROOT} &&\
    useradd -m -u ${APP_USER_UID} ${APP_USER} &&\
    usermod -G staff -a ${APP_USER} &&\
    chown -R ${APP_USER}:${APP_USER} ${APP_ROOT} &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

WORKDIR ${APP_ROOT}
