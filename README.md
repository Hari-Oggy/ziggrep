# ziggrep

A fast, multi-threaded grep implementation written in Zig. `ziggrep` is designed to be a performant and feature-rich alternative to standard grep, with built-in support for modern development workflows.

## Features

- **Recursive Search**: Recursively search directories with `-r` or `--recursive`.
- **regex Support**: Full regular expression support using a custom regex engine (`-E` / `--regex`).
- **Multi-threaded**: Leveraging Zig's `std.Thread.Pool` for high-performance parallel file processing.
- **Git Integration**: Automatically respects `.gitignore` rules (recursive, negative, and directory-specific support).
- **Smart Filtering**:
  - Filter by file type (`-t c`, `-t zig`).
  - Filter by glob pattern (`-g "*.txt"`).
  - Binary file detection and skipping.
- **User Experience**:
  - Match highlighting with color support.
  - Context line support (`-A`, `-B`, `-C`) to see surrounding code.
  - Line number reporting.

## Installation

### Prerequisites
- Zig (0.13.0 or later recommended, tested on 0.15.0-dev)

### Build
To build the project for release:

```bash
zig build -Doptimize=ReleaseSafe
```

The executable will be located at `zig-out/bin/ziggrep`.

### Install
You can add the binary to your path or use the provided install script (if applicable):

```bash
# Example manual install
sudo cp zig-out/bin/ziggrep /usr/local/bin/
```

## Usage

```bash
ziggrep [OPTIONS] PATTERN [PATHS...]
```

### Options

- `-r, --recursive`: Recursively search directories.
- `-i, --ignore-case`: Perform case-insensitive matching.
- `-n, --line-number`: specific line number of the match.
- `-E, --regex`: Treat PATTERN as a regular expression.
- `--color`: Force color output (auto-detected by default).
- `--hidden`: Search hidden files and directories (default: ignored).
- `-c, --count`: Only print the count of matching lines for each file.
- `-l, --files-with-matches`: Only print the names of files containing matches.
- `-v, --invert-match`: Select non-matching lines.

### Context Control
- `-A NUM, --after-context NUM`: Print NUM lines of trailing context.
- `-B NUM, --before-context NUM`: Print NUM lines of leading context.
- `-C NUM, --context NUM`: Print NUM lines of output context.

### Filtering
- `-t TYPE, --type TYPE`: Only search files matching TYPE (e.g., `c`, `zig`, `rust`, `python`).
- `-T TYPE, --type-not TYPE`: Exclude files matching TYPE.
- `-g GLOB, --glob GLOB`: Include files that match the given GLOB (e.g., `*.{c,h}`).

### Examples

**Basic Search**:
Search for "main" in the current directory:
```bash
ziggrep "main" .
```

**Recursive Search**:
Search for "TODO" in the `src` directory recursively:
```bash
ziggrep -r "TODO" src/
```

**Regex Search**:
Search for lines starting with "pub" followed by "fn":
```bash
ziggrep -E "^pub fn" src/
```

**File Type Filtering**:
Search only Zig files:
```bash
ziggrep -t zig "error" .
```

**Ignore Files**:
Search ignored files (force inclusion of hidden/.gitignored files):
```bash
ziggrep --hidden -r "secret" .
```

## `.gitignore` Support
`ziggrep` automatically looks for `.gitignore` files in directories it traverses. It respects:
- Standard glob patterns (`*.log`)
- Directory exclusion (`temp/`)
- Negation (`!important.log`)
- Recursive patterns (`**/node_modules`)


