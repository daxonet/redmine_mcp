#!/bin/bash
set -euo pipefail

PLUGIN_DIR="$(pwd)"

# Symlink plugin into each Redmine version
for BASE in "${REDMINE_HOME}"/*/; do
    ln -s "${PLUGIN_DIR}" "${BASE}plugins/${PLUGIN_NAME}"

    pushd "${BASE}"
    RAILS_ENV=test bundle exec rake redmine:plugins:migrate
    popd
done

# Install Node.js dependencies + Playwright browsers
npm install
npx playwright install-deps
npx playwright install
