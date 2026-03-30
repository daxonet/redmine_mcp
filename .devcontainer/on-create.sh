#!/bin/bash
set -euo pipefail

# Install system packages
apt-get update
apt-get install -y imagemagick npm shellcheck zstd

mkdir -p ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Install actionlint
curl -sL "$(curl -s https://api.github.com/repos/rhysd/actionlint/releases/latest | \
    grep -o 'https://github.com/[^"]*linux_amd64.tar.gz')" | \
    tar xz -C ~/.local/bin/ actionlint

# Install lefthook
curl -sL "$(curl -s https://api.github.com/repos/evilmartians/lefthook/releases/latest | \
    grep -o 'https://github.com/[^"]*Linux_x86_64.tar.gz')" | \
    tar xz -C ~/.local/bin/ lefthook

# Setup Redmine versions
for VERSION in 5.1 6.0 6.1; do
    TARGET="${REDMINE_HOME}/${VERSION}"

    git clone --depth 1 --branch "${VERSION}.x" https://github.com/redmine/redmine.git "${TARGET}"

    pushd "${TARGET}"

    cp config/database.yml.example config/database.yml
    sed -i 's|sqlite:db/redmine.db|sqlite:db/redmine-test.db|' config/database.yml

    RAILS_ENV=test bundle install --jobs="$(nproc)"
    RAILS_ENV=test bundle exec rake generate_secret_token
    RAILS_ENV=test bundle exec rake db:create
    RAILS_ENV=test bundle exec rake db:migrate
    RAILS_ENV=test bundle exec rake redmine:load_default_data REDMINE_LANG=en

    popd
done
