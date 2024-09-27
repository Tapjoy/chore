################################################################################
# Ruby Image
################################################################################

ARG ROOT_IMAGE
FROM ${ROOT_IMAGE} as ruby_image

# Install RVM
ENV DEBIAN_FRONTEND=noninteractive \
    GPG_SERVERS='ha.pool.sks-keyservers.net hkp://p80.pool.sks-keyservers.net:80 keyserver.ubuntu.com hkp://keyserver.ubuntu.com:80 pgp.mit.edu'
RUN apt-get update -q &&\
    apt-get upgrade -yq --no-install-recommends &&\
    apt-get install -yq --no-install-recommends curl ca-certificates &&\
    curl -sSL https://get.rvm.io >/tmp/rvm-install.sh &&\
    test "$(cat /tmp/rvm-install.sh)" &&\
    bash /tmp/rvm-install.sh stable &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install Ruby
# Switch to a login shell so we can invoke rvm
SHELL [ "/bin/bash", "-l", "-c" ]

ARG RUBY_VERSION
RUN rvm install ${RUBY_VERSION} &&\
    rvm use ${RUBY_VERSION} --default &&\
    ruby -v

ARG RUBYGEMS_VERSION
RUN gem update --system ${RUBYGEMS_VERSION}

################################################################################
# Base Image
################################################################################

FROM ruby_image as baseimage

ENV DEBIAN_FRONTEND=noninteractive LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 \
    APP_ROOT=/project APP_USER=webuser

WORKDIR ${APP_ROOT}

################################################################################
# Dev Image
################################################################################

FROM baseimage as devimage

ARG APP_USER_UID
ARG APP_USER_GID

RUN apt-get update -q &&\
    apt-get install -y --no-install-recommends sudo &&\
    echo 'webuser  ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers &&\
    rm -rf /var/lib/apt/lists/* /tmp/*

RUN mkdir -p ${APP_ROOT} &&\
    groupadd --force -g ${APP_USER_GID} ${APP_USER} &&\
    useradd -m -u ${APP_USER_UID} -g ${APP_USER_GID} ${APP_USER} -G rvm &&\
    chown -R ${APP_USER}:${APP_USER} ${APP_ROOT}

USER ${APP_USER}
