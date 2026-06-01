#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${MCP_REDMINE_SOURCE_DIR:-/opt/redmica/redmine-mcp-server-src}"
INSTALL_PATH="${MCP_REDMINE_INSTALL_PATH:-/usr/local/bin/mcp-server-redmine}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  git clone "${MCP_REDMINE_REPO_URL:-https://github.com/flor3z-github/redmine-mcp-server.git}" "${SOURCE_DIR}"
fi

git -C "${SOURCE_DIR}" fetch --all --prune
git -C "${SOURCE_DIR}" checkout "${MCP_REDMINE_REF:-develop}"
git -C "${SOURCE_DIR}" pull --ff-only || true

npm --prefix "${SOURCE_DIR}" install
npm --prefix "${SOURCE_DIR}" run build

cp -R "${SOURCE_DIR}/dist" "${TMP_DIR}/dist"
cp "${SOURCE_DIR}/package.json" "${TMP_DIR}/package.json"

cat > "${TMP_DIR}/mcp-server-redmine" <<'EOF'
#!/usr/bin/env bash
exec node /opt/redmica/redmine-mcp-server-src/dist/index.js "$@"
EOF
chmod +x "${TMP_DIR}/mcp-server-redmine"

install -m 0755 "${TMP_DIR}/mcp-server-redmine" "${INSTALL_PATH}"
echo "Installed mcp-server-redmine to ${INSTALL_PATH}"
