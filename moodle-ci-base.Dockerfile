FROM ubuntu:24.04

ARG APT_PROXY=http://172.17.0.1:3142

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=en_AU.UTF-8 \
    LC_ALL=en_AU.UTF-8

# Base tools that actions / moodle-plugin-ci expect,
# plus DB clients, build deps for PHP extensions, locales, and
# html5validator (needed by Moodle's mustache_lint_util.php).
#
# Keep this list in sync with the 'Install container prerequisites'
# step in vidyamantra/moodle-workflows .github/workflows/ci.yml.
RUN if [ -n "${APT_PROXY}" ]; then \
      echo "Acquire::http::Proxy \"${APT_PROXY}\";" > /etc/apt/apt.conf.d/01proxy; \
      echo 'Acquire::https::Proxy "DIRECT";' >> /etc/apt/apt.conf.d/01proxy; \
    fi \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      bash coreutils curl file git grep jq sudo tar unzip wget \
      ca-certificates gnupg lsb-release software-properties-common \
      python3 python3-pip \
      default-jre-headless \
      make gcc \
      libxml2-dev libzip-dev libpng-dev libonig-dev \
      locales tzdata \
      default-mysql-client postgresql-client \
 && add-apt-repository -y ppa:ondrej/php \
 && apt-get update \
 && for PHP_VERSION in 7.4 8.0 8.1 8.2 8.3 8.4; do \
      apt-get install -y --no-install-recommends \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-pgsql \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-xmlrpc \
        php${PHP_VERSION}-zip; \
    done \
 && curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php \
 && php8.4 /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer \
 && rm /tmp/composer-setup.php \
 && pip3 install --break-system-packages html5validator \
 && locale-gen en_AU.UTF-8 \
 && git config --system --add safe.directory '*' \
 && rm -rf /var/lib/apt/lists/*
