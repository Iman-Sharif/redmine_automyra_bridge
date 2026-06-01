ARG RUBY_VERSION=3.3
FROM ruby:${RUBY_VERSION}-bookworm

ARG REDMICA_REF=v3.2.6
ARG BUNDLER_WITHOUT="development test"

ENV APP_HOME=/usr/src/redmica \
    RAILS_ENV=production \
    REDMINE_LANG=en \
    BUNDLE_PATH=/usr/local/bundle

RUN set -eux; \
    printf 'Acquire::ForceIPv4 "true";\n' > /etc/apt/apt.conf.d/99force-ipv4; \
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then \
      sed -i 's|http://deb.debian.org|https://deb.debian.org|g; s|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list.d/debian.sources; \
      cat /etc/apt/sources.list.d/debian.sources; \
    fi; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
      imagemagick \
      postgresql-client \
      libpq-dev \
      pkg-config \
      python3-pip \
      shared-mime-info \
      nodejs \
      npm \
      tzdata; \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages --no-cache-dir 'lancedb==0.30.2'

WORKDIR ${APP_HOME}

RUN git clone --depth 1 --branch ${REDMICA_REF} https://github.com/redmica/redmica.git ${APP_HOME}
RUN ruby -e "paths = %w[lib/redmine/export/pdf/issues_pdf_helper.rb lib/redmine/export/pdf/wiki_pdf_helper.rb]; paths.each { |path| full = File.join(ENV.fetch('APP_HOME'), path); text = File.read(full); File.write(full, text.gsub('attachment.author.name', 'attachment.author&.name || \"-\"')) }"
COPY config/database.yml ${APP_HOME}/config/database.yml

# Modify Gemfile to use PostgreSQL instead of MySQL
RUN sed -i 's/gem "mysql2"/gem "pg", "~> 1.5"/' ${APP_HOME}/Gemfile \
 && bundle config set deployment false \
 && bundle install --jobs 4 --retry 3

COPY docker/entrypoint.sh /usr/local/bin/redmica-entrypoint
RUN chmod +x /usr/local/bin/redmica-entrypoint

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/redmica-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
