#!/usr/bin/env bash
#
# Wiki Hub Pinned Compatibility Gate Script (Task 10)
#
# Validates against pinned Redmica stack before promotion.
# Supported: my-redmica:v3.2.6-staging, Ruby 3.3.x, PostgreSQL 16
#
# Usage:
#   ./scripts/regression.sh           # Run with Docker (default)
#   ./scripts/regression.sh --docker  # Run pinned compatibility gate
#   ./scripts/regression.sh --local     # Run locally (requires Redmine environment)
#   ./scripts/regression.sh --verify-known-bad  # Verify gate rejects wrong stacks
#   ./scripts/regression.sh --help     # Show help message

set -euo pipefail

# Pinned Runtime Configuration (Task 10)
PINNED_REDMICA_IMAGE="my-redmica:v3.2.6-staging"
PINNED_RUBY_VERSION="3.3"
PINNED_POSTGRES_VERSION="16"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PLUGIN_NAME="redmine_wiki_hub"
REDMINE_DIR="${REDMINE_DIR:-/opt/redmine}"
DOCKER_COMPOSE_FILE="${PLUGIN_DIR}/test/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

show_help() {
    cat <<EOF
Wiki Hub Pinned Compatibility Gate (Task 10)

Supported: ${PINNED_REDMICA_IMAGE}, Ruby ${PINNED_RUBY_VERSION}.x, PostgreSQL ${PINNED_POSTGRES_VERSION}

Usage:
  $(basename "$0") [OPTIONS]

Options:
  --docker          Run pinned compatibility gate in Docker (default)
  --local           Run tests locally (requires Redmine environment)
  --verify-known-bad  Verify gate rejects unsupported stack configurations
  --verbose         Show detailed test output
  --help            Show this help message

Environment Variables:
  REDMINE_DIR       Path to Redmine installation (default: /opt/redmine)
  RAILS_ENV         Rails environment for local tests (default: test)

Examples:
  # Run pinned compatibility gate (default)
  ./scripts/regression.sh

  # Verify gate rejects bad configurations
  ./scripts/regression.sh --verify-known-bad

  # Run tests locally
  ./scripts/regression.sh --local

EOF
}

verify_pinned_runtime() {
    log_info "Verifying pinned runtime configuration..."
    log_info "  Supported: ${PINNED_REDMICA_IMAGE}, Ruby ${PINNED_RUBY_VERSION}.x, PostgreSQL ${PINNED_POSTGRES_VERSION}"
    
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    if ! grep -q "${PINNED_REDMICA_IMAGE}" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        log_error "Docker Compose does not use pinned Redmica image: ${PINNED_REDMICA_IMAGE}"
        exit 1
    fi
    
    if ! grep -q "postgres:16" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        log_warn "Docker Compose may not be using pinned PostgreSQL ${PINNED_POSTGRES_VERSION}"
    fi
    
    log_success "Pinned runtime configuration verified"
}

verify_known_bad() {
    log_info "Verifying known-bad compatibility guard..."
    log_info "  Testing that gate rejects unsupported stack configurations"
    
    local has_wrong_image=false
    
    if ! grep -q "my-redmica:v3.2.6-staging" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        log_error "KNOWN-BAD DETECTED: Not using pinned Redmica image (expected my-redmica:v3.2.6-staging)"
        has_wrong_image=true
    fi
    
    if grep -q "image: redmine:" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        log_error "KNOWN-BAD DETECTED: Using generic 'redmine' image instead of pinned 'my-redmica'"
        has_wrong_image=true
    fi
    
    if grep -q "image: postgres:" "$DOCKER_COMPOSE_FILE" 2>/dev/null && \
       ! grep -q "postgres:16" "$DOCKER_COMPOSE_FILE" 2>/dev/null; then
        log_error "KNOWN-BAD DETECTED: Using non-pinned PostgreSQL version (expected ${PINNED_POSTGRES_VERSION})"
        has_wrong_image=true
    fi
    
    if [[ "$has_wrong_image" == true ]]; then
        log_error "Known-bad compatibility guard: FAILED (unsupported stack detected)"
        exit 1
    fi
    
    log_success "Known-bad compatibility guard: PASSED (pinned stack confirmed)"
    return 0
}

run_docker_tests() {
    log_info "Running pinned compatibility gate with Docker..."
    log_info "  Stack: ${PINNED_REDMICA_IMAGE}, Ruby ${PINNED_RUBY_VERSION}.x, PostgreSQL ${PINNED_POSTGRES_VERSION}"
    
    if ! command -v docker-compose &> /dev/null; then
        if command -v docker &> /dev/null && docker compose version &> /dev/null; then
            DOCKER_COMPOSE="docker compose"
        else
            log_error "Docker Compose is not installed"
            exit 1
        fi
    else
        DOCKER_COMPOSE="docker-compose"
    fi
    
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        log_error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    log_info "Starting test environment..."
    
    # Clean up any existing containers
    $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" down -v 2>/dev/null || true
    
    # Start database
    $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" up -d db
    
    log_info "Waiting for database to be healthy..."
    local db_attempts=30
    local db_check=0
    while [[ $db_check -lt $db_attempts ]]; do
        if $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" ps db | grep -q "healthy"; then
            log_success "Database is healthy"
            break
        fi
        db_check=$((db_check + 1))
        sleep 2
    done
    
    # Start redmine app
    $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" up -d redmine
    
    log_info "Waiting for Redmine to be ready..."
    local max_attempts=60
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" exec -T redmine ruby -rsocket -e "TCPSocket.new('127.0.0.1', 3000).close" 2>/dev/null; then
            log_success "Redmine is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Redmine failed to start within timeout"
        $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" logs redmine --tail=50
        $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" down
        exit 1
    fi
    
    log_info "Running test suite in dedicated test container..."
    
    local exit_code=0
    
    # Run tests in the dedicated test service (clean database, no contention)
    if $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" run --rm test \
        bash -c "cd /usr/src/redmica && bundle exec rails test plugins/${PLUGIN_NAME}/test RAILS_ENV=test 2>&1"; then
        log_success "All tests passed"
    else
        exit_code=$?
        log_error "Tests failed with exit code $exit_code"
    fi
    
    log_info "Cleaning up test environment..."
    $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" down
    
    return $exit_code
}

run_local_tests() {
    log_info "Running tests locally..."
    
    if [[ ! -f "${REDMINE_DIR}/config/environment.rb" ]]; then
        log_error "Redmine directory not found at: $REDMINE_DIR"
        log_info "Set REDMINE_DIR environment variable to the correct path"
        exit 1
    fi
    
    cd "$REDMINE_DIR"
    
    if [[ ! -d "plugins/${PLUGIN_NAME}" ]]; then
        log_error "Plugin not found at: plugins/${PLUGIN_NAME}"
        exit 1
    fi
    
    log_info "Preparing test database..."
    if ! bundle exec rake db:drop db:create db:migrate RAILS_ENV=test 2>/dev/null; then
        log_warn "Database setup had issues, continuing..."
    fi
    
    log_info "Running plugin migrations..."
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test
    
    log_info "Running test suite..."
    
    local exit_code=0
    
    if bundle exec rails test "plugins/${PLUGIN_NAME}/test" RAILS_ENV=test; then
        log_success "All tests passed"
    else
        exit_code=$?
        log_error "Tests failed with exit code $exit_code"
    fi
    
    return $exit_code
}

verify_plugin_structure() {
    log_info "Verifying plugin structure..."
    
    local required_files=(
        "init.rb"
        "README.md"
        "app/controllers/wiki_hub_controller.rb"
        "app/models/wiki_hub/page_snapshot.rb"
        "app/models/wiki_hub/page_profile.rb"
        "app/models/wiki_hub/page_link.rb"
        "config/routes.rb"
    )
    
    local missing=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${PLUGIN_DIR}/${file}" ]]; then
            missing+=("$file")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required files:"
        printf '  - %s\n' "${missing[@]}"
        exit 1
    fi
    
    log_success "Plugin structure verified"
}

main() {
    local run_mode="docker"
    local verify_bad=false
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --docker)
                run_mode="docker"
                shift
                ;;
            --local)
                run_mode="local"
                shift
                ;;
            --verify-known-bad)
                verify_bad=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    echo "=================================="
    echo "Wiki Hub Pinned Compatibility Gate"
    echo "=================================="
    echo ""
    
    verify_plugin_structure
    verify_pinned_runtime
    
    if [[ "$verify_bad" == true ]]; then
        echo ""
        verify_known_bad
        echo ""
        echo "=================================="
        log_success "Known-bad verification completed"
        echo "=================================="
        exit 0
    fi
    
    echo ""
    log_info "Running tests in ${run_mode} mode..."
    log_info "Pinned stack: ${PINNED_REDMICA_IMAGE}, Ruby ${PINNED_RUBY_VERSION}.x, PostgreSQL ${PINNED_POSTGRES_VERSION}"
    echo ""
    
    local exit_code=0
    
    case $run_mode in
        docker)
            run_docker_tests
            exit_code=$?
            ;;
        local)
            run_local_tests
            exit_code=$?
            ;;
    esac
    
    echo ""
    echo "=================================="
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Pinned compatibility gate completed successfully"
    else
        log_error "Pinned compatibility gate failed"
    fi
    
    echo "=================================="
    
    exit $exit_code
}

main "$@"
