# Comprehensive Testing Guide

This guide covers the comprehensive system testing framework for Waydroid LXC, including usage, test categories, and CI/CD integration.

## Overview

The `test-complete.sh` script provides a production-ready testing framework that validates all components of your Waydroid LXC setup with detailed diagnostics, performance benchmarks, and multiple output formats.

## Features

- **Comprehensive Coverage**: Tests all system components including GPU, Waydroid, VNC, API, audio, clipboard, and networking
- **Multiple Output Formats**: Text, JSON, and HTML reports
- **Performance Benchmarks**: Measures response times and system performance
- **Detailed Diagnostics**: Provides specific error messages and actionable recommendations
- **Dual Mode**: Quick tests for fast validation or thorough tests for complete analysis
- **CI/CD Integration**: Proper exit codes and machine-readable output
- **Location Aware**: Can run from host or container with appropriate tests

## Quick Start

### Basic Usage

Run all tests with text output (default):
```bash
./scripts/test-complete.sh
```

### Quick Tests

For rapid validation during development:
```bash
./scripts/test-complete.sh --quick
```

### Thorough Tests

For complete system analysis (includes performance tests):
```bash
./scripts/test-complete.sh --thorough
```

## Output Formats

### Text Report

Human-readable text report (default):
```bash
./scripts/test-complete.sh --format text
```

Example output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  WAYDROID LXC COMPREHENSIVE TEST REPORT
  Generated: 2025-01-15 10:30:45 UTC
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EXECUTIVE SUMMARY
════════════════════════════════════════════════════════════════
  Total Tests:    45
  Passed:         42
  Failed:         1
  Warnings:       2
  Skipped:        0
  Overall Status: ⚠ PASSED WITH WARNINGS
```

### JSON Report

Machine-readable JSON for automation and CI/CD:
```bash
./scripts/test-complete.sh --format json
```

Example structure:
```json
{
  "report": {
    "version": "1.0.0",
    "generated": "2025-01-15T10:30:45Z",
    "test_mode": "thorough"
  },
  "summary": {
    "total": 45,
    "passed": 42,
    "failed": 1,
    "warnings": 2,
    "success_rate": 93.33
  },
  "tests": [
    {
      "name": "System Resources::CPU Load",
      "result": "pass",
      "message": "Load: 0.45 (0.23/core)",
      "timing_ms": 12
    }
  ]
}
```

### HTML Report

Beautiful, interactive HTML report:
```bash
./scripts/test-complete.sh --format html
```

Features:
- Color-coded test results
- Responsive design
- Performance metrics dashboard
- Detailed diagnostics for failures

### All Formats

Generate all three report formats:
```bash
./scripts/test-complete.sh --format all
```

## Test Categories

### 1. System Resources

Tests system health and capacity:
- **CPU Load**: Validates CPU usage is within acceptable limits
- **Memory Available**: Ensures sufficient memory for operations
- **Disk Space**: Checks available disk space
- **Disk I/O Performance**: Measures write speed (thorough mode only)

Thresholds:
- CPU: < 2.0 load per core
- Memory: > 512 MB available
- Disk: < 90% full

### 2. Host Configuration

Tests host-level configuration (when running on Proxmox host):
- **Proxmox Host**: Validates Proxmox VE installation
- **Kernel Modules**: Checks binder_linux and ashmem_linux are loaded
- **GPU Devices**: Verifies GPU devices are available

### 3. LXC Container Configuration

Tests container-specific setup:
- **Container Type**: Confirms running in LXC
- **GPU Device Access**: Validates /dev/dri/card0 accessibility
- **Render Node**: Checks render node availability
- **Kernel Modules**: Verifies Android modules in container

### 4. Waydroid Installation and Operation

Tests Waydroid installation and functionality:
- **Installation**: Checks Waydroid binary is installed
- **Initialization**: Validates Waydroid data directory exists
- **Container Service**: Verifies waydroid-container service status
- **Session Status**: Tests if Waydroid session is running
- **Installed Apps**: Lists installed Android apps (thorough mode)

### 5. Wayland Compositor

Tests Wayland display server:
- **Sway Compositor**: Checks if Sway is installed and running
- **Wayland Display**: Validates Wayland display socket

### 6. VNC Server

Tests VNC remote access:
- **WayVNC Installation**: Verifies wayvnc binary
- **VNC Service**: Checks waydroid-vnc service status
- **VNC Port**: Tests if port 5900 is listening
- **VNC Connection**: Attempts actual connection (thorough mode)
- **VNC Security**: Validates authentication configuration

Performance:
- Measures VNC handshake time
- Threshold: < 2000ms

### 7. API Server

Tests Home Assistant API:
- **API Script**: Checks waydroid-api.py exists
- **API Service**: Validates waydroid-api service status
- **API Port**: Tests if port 8080 is listening
- **GET /status**: Tests status endpoint
- **GET /apps**: Tests apps endpoint (thorough mode)

Performance:
- Measures API response time
- Threshold: < 1000ms

### 8. Audio System

Tests audio passthrough (thorough mode only):
- **PulseAudio**: Checks PulseAudio installation and status
- **PipeWire**: Checks PipeWire installation and status
- **Audio Devices**: Validates /dev/snd devices

### 9. Clipboard Sharing

Tests clipboard synchronization (thorough mode only):
- **wl-clipboard Tools**: Checks wl-copy and wl-paste
- **Sync Daemon**: Validates clipboard sync service
- **ADB Tools**: Verifies Android Debug Bridge installation

### 10. GPU Performance

Tests graphics acceleration (thorough mode only):
- **Direct Rendering**: Tests OpenGL direct rendering
- **Vulkan Support**: Checks Vulkan API availability
- **Intel GPU Tools**: Validates Intel GPU utilities (if applicable)

### 11. Network Connectivity

Tests network functionality:
- **DNS Resolution**: Tests domain name resolution
- **Internet Connectivity**: Pings external hosts
- **HTTP/HTTPS**: Tests web connectivity
- **Container IP**: Validates network address

## Command-Line Options

### Test Modes

| Option | Description |
|--------|-------------|
| `--quick` | Run basic tests only (faster, ~30 seconds) |
| `--thorough` | Run all tests including performance (slower, ~2 minutes) |

### Output Options

| Option | Description |
|--------|-------------|
| `--format FORMAT` | Output format: `text`, `json`, `html`, or `all` |
| `--output-dir DIR` | Directory for reports (default: `/tmp/waydroid-test-results`) |
| `--verbose, -v` | Enable verbose output with detailed diagnostics |
| `--ci` | CI/CD mode with minimal output |

### Test Location

| Option | Description |
|--------|-------------|
| `--from-host` | Run host-specific tests only |
| `--from-container` | Run container-specific tests only |
| `--auto` | Auto-detect location (default) |

### Help

| Option | Description |
|--------|-------------|
| `--help, -h` | Show help message |

## Exit Codes

The script uses standard exit codes for automation:

| Code | Meaning |
|------|---------|
| `0` | All tests passed |
| `1` | Some tests failed or warnings |
| `2` | Critical failure or setup error |

## Examples

### Development Testing

Quick validation during development:
```bash
./scripts/test-complete.sh --quick --verbose
```

### Production Validation

Thorough testing before deployment:
```bash
./scripts/test-complete.sh --thorough --format all --output-dir /var/log/waydroid-tests
```

### CI/CD Integration

Automated testing in CI pipeline:
```bash
./scripts/test-complete.sh --quick --ci --format json > test-results.json
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All tests passed"
else
    echo "✗ Tests failed with code $EXIT_CODE"
    exit $EXIT_CODE
fi
```

### Host Pre-Check

Before creating containers:
```bash
./scripts/test-complete.sh --from-host --quick
```

### Container Health Check

Inside running container:
```bash
./scripts/test-complete.sh --from-container --thorough --format html
```

## Continuous Monitoring

### Cron Job

Run tests hourly and alert on failures:
```bash
# Add to crontab
0 * * * * /path/to/scripts/test-complete.sh --quick --ci --format json > /var/log/waydroid-test-latest.json 2>&1 || /path/to/alert-script.sh
```

### Systemd Timer

Create `/etc/systemd/system/waydroid-test.timer`:
```ini
[Unit]
Description=Waydroid System Test Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
```

Create `/etc/systemd/system/waydroid-test.service`:
```ini
[Unit]
Description=Waydroid System Test

[Service]
Type=oneshot
ExecStart=/path/to/scripts/test-complete.sh --quick --ci --format json
StandardOutput=append:/var/log/waydroid-test.log
StandardError=append:/var/log/waydroid-test.log
```

Enable:
```bash
systemctl enable --now waydroid-test.timer
```

## Interpreting Results

### Success

All tests passed:
```
Overall Status: ✓ ALL TESTS PASSED
Exit Code: 0
```

Action: None required. System is healthy.

### Warnings

Some non-critical issues:
```
Overall Status: ⚠ PASSED WITH WARNINGS
Exit Code: 1
```

Action: Review warnings, but system should be functional. Address warnings when convenient.

### Failures

Critical issues detected:
```
Overall Status: ✗ TESTS FAILED
Exit Code: 1
```

Action: Review failed tests immediately. Check the "ISSUES AND RECOMMENDATIONS" section for fixes.

## Performance Metrics

The script tracks various performance metrics:

### Response Times
- **API Response Time**: Time to complete API requests (< 1000ms target)
- **VNC Handshake Time**: Time to establish VNC connection (< 2000ms target)

### System Metrics
- **CPU Load**: Per-core CPU utilization
- **Memory Usage**: Available memory in MB
- **Disk I/O**: Write speed in MB/s

### Capacity Metrics
- **GPU Devices**: Number of available GPUs
- **Waydroid Apps**: Number of installed Android apps

## Troubleshooting

### Test Script Won't Run

**Problem**: Permission denied

**Solution**:
```bash
chmod +x /path/to/scripts/test-complete.sh
```

### Tests Fail in Container

**Problem**: "Not running in LXC" error

**Solution**: Ensure you're running inside the LXC container, or use `--from-host` flag.

### Tests Timeout

**Problem**: Tests hang or take too long

**Solution**:
1. Use `--quick` mode for faster execution
2. Check network connectivity
3. Verify services are responding

### Missing Dependencies

**Problem**: "command not found" errors

**Solution**: Install required tools:
```bash
apt update
apt install curl netstat-net-tools mesa-utils vulkan-tools
```

### Reports Not Generated

**Problem**: No report files created

**Solution**:
1. Check output directory permissions
2. Verify disk space
3. Use `--output-dir` to specify writable location

## Integration with Other Tools

### Prometheus/Grafana

Export metrics for monitoring:
```bash
# Generate JSON report
./scripts/test-complete.sh --quick --format json > /var/lib/node_exporter/textfile_collector/waydroid.prom

# Convert to Prometheus format
jq -r '.metrics | to_entries | .[] | "waydroid_\(.key) \(.value)"' /tmp/test-results.json
```

### Home Assistant

Monitor test status:
```yaml
sensor:
  - platform: command_line
    name: "Waydroid Test Status"
    command: "/path/to/scripts/test-complete.sh --quick --ci --format json | jq -r '.summary.success_rate'"
    unit_of_measurement: "%"
    scan_interval: 300
```

### Slack/Discord Notifications

Alert on failures:
```bash
#!/bin/bash
./scripts/test-complete.sh --quick --format json > /tmp/test-results.json
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    FAILED=$(jq -r '.summary.failed' /tmp/test-results.json)
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"Waydroid tests failed: $FAILED tests\"}" \
        $SLACK_WEBHOOK_URL
fi
```

## Best Practices

1. **Run Quick Tests Regularly**: Use `--quick` for frequent health checks
2. **Run Thorough Tests Before Changes**: Use `--thorough` before upgrades or major changes
3. **Keep Reports**: Store reports for trend analysis and troubleshooting
4. **Automate Testing**: Set up cron jobs or systemd timers for continuous monitoring
5. **Review Warnings**: Address warnings before they become critical failures
6. **Use Verbose Mode for Debugging**: Enable `--verbose` when investigating issues
7. **CI/CD Integration**: Include tests in deployment pipelines
8. **Baseline Performance**: Run initial tests to establish performance baselines

## Advanced Usage

### Custom Thresholds

Edit the script to adjust performance thresholds:
```bash
# In test-complete.sh, modify:
declare -A PERF_THRESHOLDS=(
    ["gpu_render_time"]=5000        # ms
    ["api_response_time"]=500       # Stricter: 500ms instead of 1000ms
    ["memory_available_mb"]=1024    # Require more memory: 1GB
)
```

### Selective Category Testing

To test only specific categories, comment out test functions in the main() function:
```bash
main() {
    # ...
    test_system_resources
    # test_host_configuration  # Skip host tests
    test_lxc_configuration
    # ...
}
```

### Custom Report Formatting

The HTML report can be customized by editing the CSS in the `generate_html_report()` function.

## Waydroid Doctor

Use the built-in doctor for a fast sanity check of critical components:

```bash
# Preferred inside the container (installed by default)
waydroid-doctor.sh

# From the repository checkout
bash scripts/doctor.sh
```

It verifies binder/ashmem/binderfs availability, LXC device permissions for the `waydroid` user, required packages, Wayland socket presence, VNC port readiness, Waydroid runtime status, and API `/health` reachability. Failures include actionable guidance (for example, restarting `waydroid-container.service` or adding binder devices to the LXC config).

## Support

For issues or questions:
1. Check the ISSUES AND RECOMMENDATIONS section in test reports
2. Review logs: `journalctl -u waydroid-*`
3. Run with `--verbose` for detailed diagnostics
4. Consult other documentation in `/docs` directory

## Contributing

To add new test categories:

1. Create a new test function following the pattern:
```bash
test_new_category() {
    print_section "New Category"
    local category="New Category"
    local start_time

    start_time=$(get_timestamp_ms)
    # Your test logic here
    timing=$(($(get_timestamp_ms) - start_time))

    record_test "$category" "Test Name" "result" "message" \
        "diagnostic" "recommendation" "$timing"
}
```

2. Add to main() execution flow
3. Update this documentation

## Related Documentation

- [Installation Guide](INSTALLATION.md) - Initial setup
- [Configuration Guide](CONFIGURATION.md) - System configuration
- [Health Check Script](../scripts/health-check.sh) - Lightweight monitoring
- [Test Setup Script](../scripts/test-setup.sh) - Original test script

## Changelog

### Version 1.0.0 (2025-01-15)
- Initial release
- Comprehensive test coverage
- Multiple output formats (text, JSON, HTML)
- Performance benchmarking
- CI/CD integration support
