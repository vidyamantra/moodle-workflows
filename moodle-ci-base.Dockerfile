FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=en_AU.UTF-8 \
    LC_ALL=en_AU.UTF-8

# Base tools that setup-php / actions / moodle-plugin-ci expect,
# plus DB clients, build deps for PHP extensions, locales, and
# html5validator (needed by Moodle's mustache_lint_util.php).
#
# Keep this list in sync with the 'Install container prerequisites'
# step in vidyamantra/moodle-workflows .github/workflows/ci.yml.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash coreutils curl file git grep jq sudo tar unzip wget \
      ca-certificates gnupg lsb-release \
      python3 python3-pip \
      default-jre-headless \
      make gcc \
      libxml2-dev libzip-dev libpng-dev libonig-dev \
      locales tzdata \
      default-mysql-client postgresql-client \
 && pip3 install --break-system-packages html5validator \
 && locale-gen en_AU.UTF-8 \
 && git config --system --add safe.directory '*' \
 && rm -rf /var/lib/apt/lists/*
