# Benchmarking Guide for zig-hl

This guide explains how to use the unified benchmark tool to performance test the zig-hl highlighter
against other implementations.

## Quick Start

```bash
# Run a quick benchmark
./bench.sh quick

# Compare all build modes
./bench.sh compare

# Run multiple suites
./bench.sh quick patterns realworld

# Run everything (takes 10-30 minutes)
./bench.sh all --clean
```

## Overview

The `bench.sh` script consolidates all benchmarking functionality into a single, easy-to-use tool.

## Benchmark Suites

### quick
Fast 3-way comparison between hl, ghl (Go), and zhl (Zig). Uses a simple pattern on dictionary data with minimal runs.

**Best for:** Quick iteration during development

```bash
./bench.sh quick
./bench.sh quick --pattern "error" --test-data /var/log/system.log
```

### compare
Compares all Zig build modes (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall) with comprehensive size
analysis.

**Best for:** Understanding build mode tradeoffs

```bash
./bench.sh compare
```

### patterns
Tests multiple pattern types and modes including:
- Basic pattern matching
- Grep mode (matching lines only)
- Match-only mode
- Word matching (built-in)
- Decimal numbers
- Hex numbers

**Best for:** Validating different pattern types work correctly

```bash
./bench.sh patterns
./bench.sh patterns --runs 10
```

### scenarios
Performance characteristic analysis testing:
- Match density impact (low/medium/high)
- Line length impact (short/long)
- File size scaling (small/medium/large)

**Best for:** Understanding how performance varies with different data characteristics

```bash
./bench.sh scenarios
```

### realworld
Practical use case testing including:
- Log error analysis
- IP address extraction
- Function definition search
- Configuration parsing
- URL extraction

**Best for:** Real-world performance expectations

```bash
./bench.sh realworld
```

### comprehensive
Runs all the above suites sequentially.

**Best for:** Complete performance analysis before releases

```bash
./bench.sh comprehensive --runs 5 --warmup 2
```

### all
Runs every suite including build mode comparison. Warning: Takes significant time (10-30 minutes).

```bash
./bench.sh all --clean
```

## Options

### Basic Options

- `-h, --help` - Show help message
- `-v, --version` - Show version information
- `--verbose` - Enable verbose output

### Configuration Options

- `--runs N` - Number of benchmark runs (default: 3)
- `--warmup N` - Number of warmup runs (default: 1)
- `--output-dir DIR` - Output directory (default: benchmark-results)
- `--build-modes MODES` - Comma-separated Zig build modes
  - Options: Debug,ReleaseSafe,ReleaseFast,ReleaseSmall
  - Default: ReleaseFast
- `--clean` - Clean up generated files after completion

### Suite-Specific Options

- `--pattern PATTERN` - Pattern for quick benchmark (default: z.....)
- `--test-data FILE` - Test data file (default: /usr/share/dict/words)

## Examples

### Development Workflow

```bash
# Quick check during development
./bench.sh quick

# Test a specific pattern
./bench.sh quick --pattern "ERROR|WARN|FATAL" --test-data /var/log/app.log

# More thorough testing
./bench.sh patterns scenarios --runs 5
```

### Release Validation

```bash
# Complete analysis with cleanup
./bench.sh all --runs 10 --warmup 3 --clean
```

### Custom Configuration

```bash
# Test all build modes with custom runs
./bench.sh compare --build-modes Debug,ReleaseSafe,ReleaseFast,ReleaseSmall --runs 20

# Output to custom directory
./bench.sh comprehensive --output-dir my-results
```

## Output

Results are saved to `benchmark-results/` (or custom directory) with subdirectories for each suite:

```
benchmark-results/
├── summary.md                    # Overall summary
├── quick/
│   ├── results.json             # Detailed hyperfine results
│   └── results.md               # Markdown summary
├── patterns/
│   ├── basic.json
│   ├── basic.md
│   ├── grep.json
│   ├── grep.md
│   └── ...
├── scenarios/
│   └── ...
└── realworld/
    └── ...
```

### Reading Results

**View markdown summaries:**
```bash
cat benchmark-results/quick/results.md
cat benchmark-results/summary.md
```

**Parse JSON with jq:**
```bash
# Show mean times for all commands
jq '.results[] | {command, mean, stddev}' benchmark-results/quick/results.json

# Find fastest result
jq '.results | sort_by(.mean) | .[0]' benchmark-results/quick/results.json
```

**Compare across suites:**
```bash
# Show all mean times
find benchmark-results -name "*.json" -exec jq -r '.results[] | "\(.command): \(.mean)"' {} \;
```

## Requirements

The benchmark tool requires the following dependencies:

- **hyperfine** - Benchmark runner
  ```bash
  brew install hyperfine
  ```
  Or see: https://github.com/sharkdp/hyperfine

- **zig** - For building zhl
  ```bash
  brew install zig
  ```
  Or see: https://ziglang.org/download/

- **go** - For building ghl reference implementation
  ```bash
  brew install go
  ```
  Or see: https://golang.org/doc/install

- **hl** (optional) - External reference tool for comparison
  - If not available, comparisons with hl will be skipped

## Technical Details

### Build Process

The benchmark tool automatically builds the required binaries:

1. **Go version** (`ghl`) - Built from `ghl.go`
2. **Zig versions** (`zhl-*`) - Built with specified optimization modes
   - `zhl-Debug` - Debug build
   - `zhl-ReleaseSafe` - Release with safety checks
   - `zhl-ReleaseFast` - Maximum performance
   - `zhl-ReleaseSmall` - Minimum size

Binaries are cached between runs. To force rebuild:
```bash
rm -f ghl zhl-*
./bench.sh <suite>
```

### Test Data Generation

For scenarios that require specific data characteristics, the tool generates synthetic test data:

- **Log data** - Realistic application logs with various log levels (5,000 iterations for >5ms runtime)
- **Source code** - C code samples with functions and error handling (3,000 files for >5ms runtime)
- **Configuration files** - Key-value config with various patterns (1,000 environments for >5ms runtime)
- **Density data** - Controlled match frequency (1%, 10%, 50%)

Test data sizes are chosen to ensure benchmarks take at least 5ms to run, which provides more
accurate timing measurements. Generated data is stored in `bench-tmp/` and can be cleaned up with
`--clean`.

### Cleanup

Clean up generated files:

```bash
# Manual cleanup
rm -rf bench-tmp benchmark-results ghl zhl-*

# Or use --clean flag
./bench.sh quick --clean
```

## Troubleshooting

### "No readable test data found"

The default test data is `/usr/share/dict/words`. If not available, specify an alternative:

```bash
./bench.sh quick --test-data /etc/passwd
```

### "Missing required dependencies"

Install the missing tools as shown in the error message. All tools are available via Homebrew on
macOS or standard package managers on Linux.

### "hl not found - some comparisons will be skipped"

The external [`hl`](https://github.com/Grazfather/dotfiles/blob/master/bin/hl) tool is optional.
Benchmarks will run without it, comparing only `ghl` and `zhl`.

### Benchmark takes too long

Reduce runs and warmup:

```bash
./bench.sh quick --runs 1 --warmup 0
```

Or run only specific suites instead of `all`.

## Contributing

When adding new benchmark scenarios:

1. Add a new suite function (e.g., `suite_newsuite()`)
2. Register it in the main switch statement
3. Add help text in `show_help()`
4. Update this documentation

## See Also

- `./bench.sh --help` - Full command-line help
- [`hl`](https://github.com/Grazfather/dotfiles/blob/master/bin/hl) - My original babashka/clojure
  version of this tool.
- [Hyperfine documentation](https://github.com/sharkdp/hyperfine)
- [Project README](README.md)
