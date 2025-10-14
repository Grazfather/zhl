#!/bin/bash

# Unified benchmark tool for zig-hl highlighter comparison
# Consolidates all benchmark functionality into a single script

set -e

# ============================================================================
# Configuration and Constants
# ============================================================================

VERSION="2.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_RUNS=3
DEFAULT_WARMUP=1
DEFAULT_OUTPUT_DIR="benchmark-results"
DEFAULT_TMP_DIR="bench-tmp"
DEFAULT_PATTERN="z....."
DEFAULT_TEST_DATA="/usr/share/dict/words"

# Configuration variables (can be overridden by options)
RUNS=$DEFAULT_RUNS
WARMUP=$DEFAULT_WARMUP
OUTPUT_DIR=$DEFAULT_OUTPUT_DIR
TMP_DIR=$DEFAULT_TMP_DIR
CLEAN_AFTER=false
BUILD_MODES="ReleaseFast"
VERBOSE=false

# ============================================================================
# Help and Usage
# ============================================================================

show_help() {
    echo -e "${BLUE}bench.sh${NC} - Unified benchmark tool for zig-hl highlighter comparison"
    echo ""
    echo -e "${YELLOW}USAGE:${NC}"
    echo "    bench.sh [OPTIONS] [SUITE...]"
    echo ""
    echo -e "${YELLOW}BENCHMARK SUITES:${NC}"
    echo -e "    ${GREEN}quick${NC}         Fast 3-way comparison (hl, ghl, zhl)"
    echo "                  Single pattern on dictionary, minimal runs"
    echo "                  Best for: Quick iteration during development"
    echo ""
    echo -e "    ${GREEN}compare${NC}       Build mode comparison with size analysis"
    echo "                  Tests Debug, ReleaseSafe, ReleaseFast, ReleaseSmall"
    echo "                  Shows size vs. performance tradeoffs"
    echo ""
    echo -e "    ${GREEN}patterns${NC}      Multiple pattern types and modes"
    echo "                  Tests: basic, grep, match-only, words, decimals, hex"
    echo "                  Best for: Validating different pattern types"
    echo ""
    echo -e "    ${GREEN}scenarios${NC}     Performance characteristic analysis"
    echo "                  Tests: match density, line length, regex complexity,"
    echo "                        mode comparison, file size scaling"
    echo "                  Best for: Understanding performance behavior"
    echo ""
    echo -e "    ${GREEN}realworld${NC}     Practical use case testing"
    echo "                  Tests: log analysis, code search, config parsing"
    echo "                  Best for: Real-world performance expectations"
    echo ""
    echo -e "    ${GREEN}comprehensive${NC} Full test suite with synthetic data"
    echo "                  10+ scenarios with varied data types and patterns"
    echo "                  Best for: Complete performance analysis"
    echo ""
    echo -e "    ${GREEN}all${NC}           Run all benchmark suites"
    echo "                  Warning: Takes significant time (~10-30 minutes)"
    echo ""
    echo -e "${YELLOW}OPTIONS:${NC}"
    echo "    -h, --help              Show this help message"
    echo "    -v, --version           Show version information"
    echo "    --verbose               Enable verbose output"
    echo "    --runs N                Number of benchmark runs (default: $DEFAULT_RUNS)"
    echo "    --warmup N              Number of warmup runs (default: $DEFAULT_WARMUP)"
    echo "    --output-dir DIR        Output directory (default: $DEFAULT_OUTPUT_DIR)"
    echo "    --build-modes MODES     Comma-separated Zig build modes"
    echo "                           (default: ReleaseFast)"
    echo "                           Options: Debug,ReleaseSafe,ReleaseFast,ReleaseSmall"
    echo "    --clean                 Clean up generated files after completion"
    echo "    --pattern PATTERN       Pattern for quick benchmark (default: $DEFAULT_PATTERN)"
    echo "    --test-data FILE        Test data file (default: $DEFAULT_TEST_DATA)"
    echo ""
    echo -e "${YELLOW}EXAMPLES:${NC}"
    echo -e "    ${CYAN}# Quick comparison during development${NC}"
    echo "    bench.sh quick"
    echo ""
    echo -e "    ${CYAN}# Compare all build modes${NC}"
    echo "    bench.sh compare --build-modes Debug,ReleaseSafe,ReleaseFast,ReleaseSmall"
    echo ""
    echo -e "    ${CYAN}# Test specific pattern types${NC}"
    echo "    bench.sh patterns --runs 5"
    echo ""
    echo -e "    ${CYAN}# Run real-world scenarios and clean up${NC}"
    echo "    bench.sh realworld --clean"
    echo ""
    echo -e "    ${CYAN}# Full analysis with custom runs${NC}"
    echo "    bench.sh all --runs 10 --warmup 3"
    echo ""
    echo -e "    ${CYAN}# Multiple suites${NC}"
    echo "    bench.sh quick patterns scenarios"
    echo ""
    echo -e "${YELLOW}OUTPUT:${NC}"
    echo -e "    Results are saved to ${CYAN}$DEFAULT_OUTPUT_DIR/${NC} with subdirectories:"
    echo "    - $DEFAULT_OUTPUT_DIR/quick/"
    echo "    - $DEFAULT_OUTPUT_DIR/compare/"
    echo "    - $DEFAULT_OUTPUT_DIR/patterns/"
    echo "    - $DEFAULT_OUTPUT_DIR/scenarios/"
    echo "    - $DEFAULT_OUTPUT_DIR/realworld/"
    echo "    - $DEFAULT_OUTPUT_DIR/comprehensive/"
    echo ""
    echo "    Each suite generates:"
    echo "    - *.json files (detailed hyperfine results)"
    echo "    - *.md files (markdown summaries)"
    echo "    - summary.md (overall results)"
    echo ""
    echo -e "${YELLOW}REQUIREMENTS:${NC}"
    echo "    - hyperfine (benchmark tool)"
    echo "    - zig (for building zhl)"
    echo "    - go (for building ghl)"
    echo "    - hl (optional, external reference tool)"
    echo ""
}

show_version() {
    echo "bench.sh version $VERSION"
    echo "Unified benchmark tool for zig-hl highlighter"
}

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_section() {
    echo ""
    echo -e "${MAGENTA}=====================================================================${NC}"
    echo -e "${MAGENTA}$*${NC}"
    echo -e "${MAGENTA}=====================================================================${NC}"
    echo ""
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[VERBOSE]${NC} $*"
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check if binary exists and is executable
binary_exists() {
    [[ -x "$1" ]]
}

# Get file size in human-readable format
get_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        ls -lh "$file" | awk '{print $5}'
    else
        echo "N/A"
    fi
}

# Get line count
get_line_count() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -l < "$file"
    else
        echo "0"
    fi
}

# Get byte count
get_byte_count() {
    local file="$1"
    if [[ -f "$file" ]]; then
        wc -c < "$file"
    else
        echo "0"
    fi
}

# ============================================================================
# Dependency Checking
# ============================================================================

check_dependencies() {
    log_info "Checking dependencies..."

    local missing=()

    if ! command_exists hyperfine; then
        missing+=("hyperfine")
    fi

    if ! command_exists zig; then
        missing+=("zig")
    fi

    if ! command_exists go; then
        missing+=("go")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Installation instructions:"
        for dep in "${missing[@]}"; do
            case "$dep" in
                hyperfine)
                    echo "  hyperfine: brew install hyperfine  (or see https://github.com/sharkdp/hyperfine)"
                    ;;
                zig)
                    echo "  zig: brew install zig  (or see https://ziglang.org/download/)"
                    ;;
                go)
                    echo "  go: brew install go  (or see https://golang.org/doc/install)"
                    ;;
            esac
        done
        exit 1
    fi

    if ! command_exists hl; then
        log_warn "'hl' not found - some comparisons will be skipped"
    fi

    log_success "All required dependencies found"
}

# ============================================================================
# Build Functions
# ============================================================================

build_go() {
    log_info "Building Go version..."

    if [[ ! -f "ghl.go" ]]; then
        log_warn "ghl.go not found, skipping Go build"
        return 1
    fi

    go build -o ghl ghl.go

    if ! binary_exists "./ghl"; then
        log_error "Failed to build Go version"
        return 1
    fi

    log_success "Go version built: $(get_size ./ghl)"
    return 0
}

build_zig() {
    local mode="$1"
    log_info "Building Zig $mode mode..."

    if ! zig build -Doptimize="$mode"; then
        log_error "Failed to build Zig $mode version"
        return 1
    fi

    # Copy to specific binary name
    cp zig-out/bin/zhl "zhl-$mode"
    chmod +x "zhl-$mode"

    log_success "Zig $mode built: $(get_size "./zhl-$mode")"
    return 0
}

build_all() {
    log_section "Building All Versions"

    local build_failed=false

    # Build Go version
    if ! build_go; then
        build_failed=true
    fi

    # Build Zig versions
    IFS=',' read -ra MODES <<< "$BUILD_MODES"
    for mode in "${MODES[@]}"; do
        if ! build_zig "$mode"; then
            build_failed=true
        fi
    done

    if [[ "$build_failed" == "true" ]]; then
        log_error "Some builds failed"
        exit 1
    fi

    log_success "All builds completed successfully"
}

# Get list of available tools for benchmarking
get_available_tools() {
    local tools=()

    # Check for hl (external)
    if command_exists hl; then
        tools+=("hl")
    fi

    # Check for ghl (Go)
    if binary_exists "./ghl"; then
        tools+=("ghl")
    fi

    # Check for zhl variants
    IFS=',' read -ra MODES <<< "$BUILD_MODES"
    for mode in "${MODES[@]}"; do
        if binary_exists "./zhl-$mode"; then
            tools+=("zhl-$mode")
        fi
    done

    printf '%s\n' "${tools[@]}"
}

# ============================================================================
# Data Generation Functions
# ============================================================================

# Generate realistic log data
generate_log_data() {
    local output_file="$1"
    local lines="${2:-5000}"  # Increased from 1000 to ensure tests take >5ms

    log_verbose "Generating log data: $output_file ($lines iterations)"

    cat > "$output_file.base" << 'EOF'
2024-01-15 10:30:45 INFO  [main] Application started successfully
2024-01-15 10:30:46 DEBUG [auth] User authentication attempt for user: john.doe@company.com
2024-01-15 10:30:46 INFO  [auth] User john.doe@company.com authenticated successfully
2024-01-15 10:30:47 DEBUG [db] Database connection established to 192.168.1.50:5432
2024-01-15 10:30:48 INFO  [api] GET /api/users/123 - 200 OK (45ms)
2024-01-15 10:30:49 WARN  [cache] Cache miss for key: user_profile_123
2024-01-15 10:30:50 ERROR [payment] Payment processing failed for transaction tx_456789: connection timeout
2024-01-15 10:30:51 INFO  [api] POST /api/orders - 201 Created (120ms)
2024-01-15 10:30:52 DEBUG [queue] Message queued: order_notification_789
2024-01-15 10:30:53 ERROR [email] Failed to send email to customer@example.com: SMTP server unavailable
EOF

    for i in $(seq 1 "$lines"); do
        sed "s/john\.doe/user$i/g; s/123/$((i + 100))/g; s/192\.168\.1\.50/192.168.1.$((i % 100 + 1))/g" "$output_file.base"
    done > "$output_file"

    rm "$output_file.base"
}

# Generate source code data
generate_code_data() {
    local output_file="$1"
    local files="${2:-3000}"  # Increased to 3000 to ensure tests take >5ms

    log_verbose "Generating code data: $output_file ($files files)"

    cat > "$output_file.base" << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int process_request(const char *data) {
    if (data == NULL) {
        fprintf(stderr, "ERROR: null data\n");
        return -1;
    }
    printf("Processing: %s\n", data);
    return 0;
}

void handle_error(int code, const char *msg) {
    fprintf(stderr, "ERROR %d: %s\n", code, msg);
    exit(code);
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        handle_error(1, "insufficient arguments");
    }
    return process_request(argv[1]);
}
EOF

    for i in $(seq 1 "$files"); do
        sed "s/process_request/process_request_$i/g; s/handle_error/handle_error_$i/g" "$output_file.base"
    done > "$output_file"

    rm "$output_file.base"
}

# Generate config data
generate_config_data() {
    local output_file="$1"
    local envs="${2:-1000}"  # Increased to 1000 to ensure tests take >5ms

    log_verbose "Generating config data: $output_file ($envs environments)"

    cat > "$output_file.base" << 'EOF'
# Database configuration
db.host=localhost
db.port=5432
db.user=app_user
db.password=secret123
db.name=production_db

# API settings
api.base_url=https://api.company.com/v1
api.timeout=30000
api.retry_count=3
api.key=sk_live_abc123def456

# Cache settings
cache.enabled=true
cache.host=redis.company.com
cache.port=6379
cache.ttl=3600
EOF

    for env in dev staging prod; do
        for i in $(seq 1 "$envs"); do
            sed "s/production_db/${env}_db_$i/g; s/localhost/${env}-db-$i.company.com/g" "$output_file.base"
        done
    done > "$output_file"

    rm "$output_file.base"
}

# Generate test data with specific characteristics
generate_density_data() {
    local output_file="$1"
    local density="$2"  # low, medium, high
    local lines="${3:-10000}"

    log_verbose "Generating $density density data: $output_file ($lines lines)"

    case "$density" in
        low)
            # 1% match rate
            seq 1 "$lines" | awk 'NR % 100 == 1 {print "target_" $0 "_match"} NR % 100 != 1 {print "normal_line_" $0}' > "$output_file"
            ;;
        medium)
            # 10% match rate
            seq 1 "$lines" | awk 'NR % 10 == 1 {print "target_" $0 "_match"} NR % 10 != 1 {print "normal_line_" $0}' > "$output_file"
            ;;
        high)
            # 50% match rate
            seq 1 "$lines" | awk 'NR % 2 == 1 {print "target_" $0 "_match"} NR % 2 != 1 {print "normal_line_" $0}' > "$output_file"
            ;;
    esac
}

# ============================================================================
# Benchmark Execution Functions
# ============================================================================

# Run hyperfine benchmark with consistent options
run_hyperfine() {
    local output_file="$1"
    shift
    local commands=("$@")

    log_verbose "Running hyperfine: ${#commands[@]} commands, output: $output_file"

    if [[ ${#commands[@]} -eq 0 ]]; then
        log_warn "No commands to benchmark, skipping"
        return 1
    fi

    if ! hyperfine \
        --runs "$RUNS" \
        --warmup "$WARMUP" \
        --export-json "$output_file.json" \
        --export-markdown "$output_file.md" \
        "${commands[@]}"; then
            log_error "Benchmark failed"
            return 1
    fi

    return 0
}

# Build benchmark command for a tool
build_benchmark_cmd() {
    local tool="$1"
    local test_file="$2"
    local pattern="$3"
    local extra_args="$4"

    # Determine command based on tool
    case "$tool" in
        hl)
            echo "cat '$test_file' | hl -p '$pattern' $extra_args > /dev/null"
            ;;
        ghl)
            echo "cat '$test_file' | ./ghl -p '$pattern' $extra_args > /dev/null"
            ;;
        zhl-*)
            echo "cat '$test_file' | ./$tool -p '$pattern' $extra_args > /dev/null"
            ;;
        *)
            log_error "Unknown tool: $tool"
            return 1
            ;;
    esac
}

# ============================================================================
# Benchmark Suite: Quick
# ============================================================================

suite_quick() {
    log_section "Quick Benchmark Suite"

    local suite_dir="$OUTPUT_DIR/quick"
    mkdir -p "$suite_dir"

    local pattern="${QUICK_PATTERN:-$DEFAULT_PATTERN}"
    local test_data="${QUICK_TEST_DATA:-$DEFAULT_TEST_DATA}"

    if [[ ! -r "$test_data" ]]; then
        log_error "Test data not readable: $test_data"
        return 1
    fi

    log_info "Pattern: $pattern"
    log_info "Test data: $test_data ($(get_line_count "$test_data") lines)"

    # Build commands for available tools
    local commands=()
    local tools=($(get_available_tools))

    for tool in "${tools[@]}"; do
        cmd=$(build_benchmark_cmd "$tool" "$test_data" "$pattern" "")
        commands+=("$cmd")
    done

    if [[ ${#commands[@]} -eq 0 ]]; then
        log_error "No tools available for benchmarking"
        return 1
    fi

    log_info "Testing ${#commands[@]} tools..."
    run_hyperfine "$suite_dir/results" "${commands[@]}"

    log_success "Quick benchmark complete"
    log_info "Results: $suite_dir/results.json"
}

# ============================================================================
# Benchmark Suite: Compare
# ============================================================================

suite_compare() {
    log_section "Build Mode Comparison Suite"

    local suite_dir="$OUTPUT_DIR/compare"
    mkdir -p "$suite_dir"

    # Build all modes for comparison
    local orig_modes="$BUILD_MODES"
    BUILD_MODES="Debug,ReleaseSafe,ReleaseFast,ReleaseSmall"
    build_all
    BUILD_MODES="$orig_modes"

    # Show binary sizes
    log_info "Binary sizes:"
    echo ""
    printf "%-20s | %s\n" "Binary" "Size"
    echo "---------------------+----------"

    for binary in ghl zhl-*; do
        if binary_exists "./$binary"; then
            size=$(get_size "./$binary")
            printf "%-20s | %s\n" "$binary" "$size"
        fi
    done
    echo ""

    # Run benchmark with all tools
    local test_data="$DEFAULT_TEST_DATA"
    local pattern="$DEFAULT_PATTERN"

    if [[ ! -r "$test_data" ]]; then
        log_warn "Default test data not found, using /etc/passwd"
        test_data="/etc/passwd"
    fi

    local commands=()

    if command_exists hl; then
        commands+=("cat '$test_data' | hl -p '$pattern' > /dev/null")
    fi

    if binary_exists "./ghl"; then
        commands+=("cat '$test_data' | ./ghl -p '$pattern' > /dev/null")
    fi

    for mode in Debug ReleaseSafe ReleaseFast ReleaseSmall; do
        if binary_exists "./zhl-$mode"; then
            commands+=("cat '$test_data' | ./zhl-$mode -p '$pattern' > /dev/null")
        fi
    done

    log_info "Running benchmark with ${#commands[@]} configurations..."
    run_hyperfine "$suite_dir/results" "${commands[@]}"

    log_success "Build mode comparison complete"
    log_info "Results: $suite_dir/results.json"
}

# ============================================================================
# Benchmark Suite: Patterns
# ============================================================================

suite_patterns() {
    log_section "Pattern Types Suite"

    local suite_dir="$OUTPUT_DIR/patterns"
    mkdir -p "$suite_dir"

    local test_data="$DEFAULT_TEST_DATA"
    if [[ ! -r "$test_data" ]]; then
        test_data="/etc/passwd"
    fi

    # Test 1: Basic pattern
    log_info "Test 1: Basic pattern matching"
    local commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$test_data" "z....." "")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/basic" "${commands[@]}"

    # Test 2: Grep mode
    log_info "Test 2: Grep mode (matching lines only)"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$test_data" "e" "-g")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/grep" "${commands[@]}"

    # Test 3: Match-only mode
    log_info "Test 3: Match-only mode"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$test_data" "[aeiou]+" "-m")
        commands+=("$cmd")
    done
    if [[ ${#commands[@]} -gt 0 ]]; then
        run_hyperfine "$suite_dir/match-only" "${commands[@]}"
    fi

    # Test 4: Word matching (built-in)
    log_info "Test 4: Word matching"
    commands=()
    for tool in $(get_available_tools); do
        case "$tool" in
            hl)
                commands+=("cat '$test_data' | hl -w > /dev/null")
                ;;
            ghl)
                commands+=("cat '$test_data' | ./ghl -w > /dev/null")
                ;;
            zhl-*)
                commands+=("cat '$test_data' | ./$tool -w > /dev/null")
                ;;
        esac
    done
    if [[ ${#commands[@]} -gt 0 ]]; then
        run_hyperfine "$suite_dir/words" "${commands[@]}"
    fi

    # Test 5: Decimal numbers
    log_info "Test 5: Decimal number matching"
    commands=()
    for tool in $(get_available_tools); do
        case "$tool" in
            hl)
                commands+=("cat '$test_data' | hl -d > /dev/null")
                ;;
            ghl)
                commands+=("cat '$test_data' | ./ghl -d > /dev/null")
                ;;
            zhl-*)
                commands+=("cat '$test_data' | ./$tool -d > /dev/null")
                ;;
        esac
    done
    if [[ ${#commands[@]} -gt 0 ]]; then
        run_hyperfine "$suite_dir/decimals" "${commands[@]}"
    fi

    # Test 6: Hex numbers
    log_info "Test 6: Hex number matching"
    commands=()
    for tool in $(get_available_tools); do
        case "$tool" in
            hl)
                commands+=("cat '$test_data' | hl -x > /dev/null")
                ;;
            ghl)
                commands+=("cat '$test_data' | ./ghl -x > /dev/null")
                ;;
            zhl-*)
                commands+=("cat '$test_data' | ./$tool -x > /dev/null")
                ;;
        esac
    done
    if [[ ${#commands[@]} -gt 0 ]]; then
        run_hyperfine "$suite_dir/hex" "${commands[@]}"
    fi

    log_success "Pattern types suite complete"
    log_info "Results: $suite_dir/*.json"
}

# ============================================================================
# Benchmark Suite: Scenarios
# ============================================================================

suite_scenarios() {
    log_section "Performance Scenarios Suite"

    local suite_dir="$OUTPUT_DIR/scenarios"
    mkdir -p "$suite_dir"
    mkdir -p "$TMP_DIR"

    # Scenario 1: Match density impact
    log_info "Scenario 1: Match density impact"
    for density in low medium high; do
        generate_density_data "$TMP_DIR/density-$density.txt" "$density" 10000

        local commands=()
        for tool in $(get_available_tools); do
            cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/density-$density.txt" "target.*match" "")
            commands+=("$cmd")
        done

        run_hyperfine "$suite_dir/density-$density" "${commands[@]}"
    done

    # Scenario 2: Line length impact
    log_info "Scenario 2: Line length impact"

    # Short lines
    seq 1 50000 | awk '{print "word" $0}' > "$TMP_DIR/short-lines.txt"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/short-lines.txt" "[0-9]+" "")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/line-length-short" "${commands[@]}"

    # Long lines
    seq 1 5000 | awk '{printf "{\"timestamp\":\"%d\",\"data\":\"padding_to_make_line_long_%d\"}\n", $0, $0}' > "$TMP_DIR/long-lines.txt"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/long-lines.txt" "[0-9]+" "")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/line-length-long" "${commands[@]}"

    # Scenario 3: File size scaling
    log_info "Scenario 3: File size scaling"

    for size in small medium large; do
        case "$size" in
            small)
                lines=1000
                ;;
            medium)
                lines=10000
                ;;
            large)
                lines=100000
                ;;
        esac

        seq 1 "$lines" | sed "s/^/This is line /; s/$/ with test data/" > "$TMP_DIR/size-$size.txt"

        commands=()
        for tool in $(get_available_tools); do
            cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/size-$size.txt" "line" "")
            commands+=("$cmd")
        done

        run_hyperfine "$suite_dir/filesize-$size" "${commands[@]}"
    done

    log_success "Performance scenarios suite complete"
    log_info "Results: $suite_dir/*.json"
}

# ============================================================================
# Benchmark Suite: Real-world
# ============================================================================

suite_realworld() {
    log_section "Real-world Usage Suite"

    local suite_dir="$OUTPUT_DIR/realworld"
    mkdir -p "$suite_dir"
    mkdir -p "$TMP_DIR"

    # Generate test data (using defaults which are now larger)
    log_info "Generating realistic test data..."
    generate_log_data "$TMP_DIR/logs.txt"
    generate_code_data "$TMP_DIR/code.c"
    generate_config_data "$TMP_DIR/config.txt"

    # Scenario 1: Log error analysis
    log_info "Scenario 1: Finding errors in logs (grep mode)"
    local commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/logs.txt" "(ERROR|WARN|FATAL)" "-g")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/log-errors" "${commands[@]}"

    # Scenario 2: IP extraction
    log_info "Scenario 2: Extracting IP addresses (match-only mode)"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/logs.txt" "([0-9]{1,3}\.){3}[0-9]{1,3}" "-m")
        commands+=("$cmd")
    done
    if [[ ${#commands[@]} -gt 0 ]]; then
        run_hyperfine "$suite_dir/ip-extraction" "${commands[@]}"
    fi

    # Scenario 3: Function definitions in code
    log_info "Scenario 3: Finding function definitions"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/code.c" "^[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(" "-g")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/function-search" "${commands[@]}"

    # Scenario 4: Config value extraction
    log_info "Scenario 4: Database config search"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/config.txt" "^db\." "-g")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/config-search" "${commands[@]}"

    # Scenario 5: URL extraction
    log_info "Scenario 5: URL extraction"
    commands=()
    for tool in $(get_available_tools); do
        cmd=$(build_benchmark_cmd "$tool" "$TMP_DIR/config.txt" "https?://[a-zA-Z0-9.-]+[a-zA-Z0-9./_-]*" "")
        commands+=("$cmd")
    done
    run_hyperfine "$suite_dir/url-extraction" "${commands[@]}"

    log_success "Real-world usage suite complete"
    log_info "Results: $suite_dir/*.json"
}

# ============================================================================
# Benchmark Suite: Comprehensive
# ============================================================================

suite_comprehensive() {
    log_section "Comprehensive Test Suite"

    log_info "Running all test suites..."

    suite_quick
    suite_patterns
    suite_scenarios
    suite_realworld

    log_success "Comprehensive suite complete"
}

# ============================================================================
# Cleanup Functions
# ============================================================================

cleanup() {
    log_info "Cleaning up generated files..."

    # Remove temp directories
    rm -rf "$TMP_DIR"

    # Remove built binaries
    rm -f ghl zhl-*

    # Remove old benchmark files in root
    rm -f benchmark*.csv benchmark*.json benchmark*.md

    log_success "Cleanup complete"
}

# ============================================================================
# Summary and Reporting
# ============================================================================

generate_summary() {
    log_info "Generating summary report..."

    local summary_file="$OUTPUT_DIR/summary.md"

    cat > "$summary_file" << EOF
# Benchmark Summary

**Generated:** $(date)
**Configuration:**
- Runs: $RUNS
- Warmup: $WARMUP
- Build modes: $BUILD_MODES

## Binary Sizes

| Binary | Size |
|--------|------|
EOF

    # Add binary sizes
    for binary in ghl zhl-*; do
        if binary_exists "./$binary"; then
            size=$(get_size "./$binary")
            echo "| $binary | $size |" >> "$summary_file"
        fi
    done

    cat >> "$summary_file" << EOF

## Results by Suite

Results are organized in subdirectories:

EOF

    # List suite directories
    for suite in quick compare patterns scenarios realworld comprehensive; do
        if [[ -d "$OUTPUT_DIR/$suite" ]]; then
            echo "- **$suite/**: $(ls "$OUTPUT_DIR/$suite"/*.json 2>/dev/null | wc -l | tr -d ' ') test(s)" >> "$summary_file"
        fi
    done

    cat >> "$summary_file" << EOF

## How to Read Results

Each suite directory contains:
- \`*.json\` - Detailed hyperfine results with timing data
- \`*.md\` - Markdown formatted results for easy reading

Use \`jq\` to parse JSON files:
\`\`\`bash
jq '.results[] | {command, mean, stddev}' $OUTPUT_DIR/quick/results.json
\`\`\`

Or view markdown files directly:
\`\`\`bash
cat $OUTPUT_DIR/quick/results.md
\`\`\`

EOF

    log_success "Summary report generated: $summary_file"
}

# ============================================================================
# Main Execution
# ============================================================================

parse_arguments() {
    local suites=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --runs)
                RUNS="$2"
                shift 2
                ;;
            --warmup)
                WARMUP="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --build-modes)
                BUILD_MODES="$2"
                shift 2
                ;;
            --clean)
                CLEAN_AFTER=true
                shift
                ;;
            --pattern)
                QUICK_PATTERN="$2"
                shift 2
                ;;
            --test-data)
                QUICK_TEST_DATA="$2"
                shift 2
                ;;
            quick|compare|patterns|scenarios|realworld|comprehensive|all)
                suites+=("$1")
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Default to quick if no suites specified
    if [[ ${#suites[@]} -eq 0 ]]; then
        suites=("quick")
    fi

    printf '%s\n' "${suites[@]}"
}

main() {
    # Handle --help and --version early to avoid output capture issues
    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
        esac
    done

    local start_time=$(date +%s)

    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                    ║"
    echo "║              Unified Benchmark Tool for zig-hl                     ║"
    echo "║                         Version $VERSION                              ║"
    echo "║                                                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Parse arguments and get suite list
    local suites=($(parse_arguments "$@"))

    log_info "Configuration:"
    echo "  Runs: $RUNS"
    echo "  Warmup: $WARMUP"
    echo "  Output: $OUTPUT_DIR"
    echo "  Build modes: $BUILD_MODES"
    echo "  Suites: ${suites[*]}"
    echo ""

    # Check dependencies
    check_dependencies

    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$TMP_DIR"

    # Build all required binaries
    build_all

    # Run selected suites
    for suite in "${suites[@]}"; do
        case "$suite" in
            quick)
                suite_quick
                ;;
            compare)
                suite_compare
                ;;
            patterns)
                suite_patterns
                ;;
            scenarios)
                suite_scenarios
                ;;
            realworld)
                suite_realworld
                ;;
            comprehensive)
                suite_comprehensive
                ;;
            all)
                suite_quick
                suite_compare
                suite_patterns
                suite_scenarios
                suite_realworld
                ;;
            *)
                log_error "Unknown suite: $suite"
                ;;
        esac
    done

    # Generate summary
    generate_summary

    # Clean up if requested
    if [[ "$CLEAN_AFTER" == "true" ]]; then
        cleanup
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_section "Benchmark Complete"

    log_success "All benchmarks completed successfully!"
    echo ""
    echo "  Total time: ${duration}s"
    echo "  Results: $OUTPUT_DIR/"
    echo "  Summary: $OUTPUT_DIR/summary.md"
    echo ""

    if [[ "$CLEAN_AFTER" != "true" ]]; then
        echo "  Cleanup: bench.sh --clean (or manually: rm -rf $TMP_DIR ghl zhl-*)"
    fi

    echo ""
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
