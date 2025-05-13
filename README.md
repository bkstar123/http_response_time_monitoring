# HTTP Response Time Monitoring

A bash script for monitoring HTTP response time of .NET Core applications and automatically collecting diagnostics when response time exceeds threshold.

## Quick Start

1. Make sure you have required tools installed:
   - curl
   - bc
   - dotnet-dump
   - dotnet-trace
   - azcopy

2. Make script executable:
   ```bash
   chmod +x resp_monitoring.sh
   ```

3. Run with default settings (monitors http://localhost:80 every 10s with 1000ms threshold):
   ```bash
   ./resp_monitoring.sh
   ```

## Common Usage Examples

1. Monitor specific URL with custom threshold:
   ```bash
   ./resp_monitoring.sh -l http://myapp:8080 -t 2000
   ```

2. Enable memory dump collection with 30s polling:
   ```bash
   ./resp_monitoring.sh -f 30 enable-dump
   ```

3. Monitor with both dump and trace collection:
   ```bash
   ./resp_monitoring.sh -t 1500 -l http://myapp:8080 enable-dump-trace
   ```

4. Clean up monitoring processes:
   ```bash
   ./resp_monitoring.sh -c
   ```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-t` | Response time threshold (ms) | 1000 |
| `-l` | URL to monitor | http://localhost:80 |
| `-f` | Polling frequency (seconds) | 10 |
| `-h` | Show help message | - |
| `-c` | Clean up processes | - |

## Diagnostic Options

| Option | Description |
|--------|-------------|
| `enable-dump` | Collect memory dumps |
| `enable-trace` | Collect profiler traces |
| `enable-dump-trace` | Collect both |

## Output Files

- Logs: `resptime-logs-<instance>/resptime_stats_YYYY-MM-DD_HH.log`
- Dumps: `dump_<instance>_YYYYMMDD_HHMMSS.dmp`
- Traces: `trace_<instance>_YYYYMMDD_HHMMSS.nettrace`

All diagnostic files are automatically uploaded to Azure Blob Storage.

## Troubleshooting

1. Script not collecting diagnostics:
   - Check if threshold is appropriate
   - Verify process permissions
   - Validate Azure credentials

2. Failed uploads:
   - Check network connectivity
   - Verify SAS URL is valid and not expired
   - Ensure Azure storage permissions are correct

3. Missing logs:
   - Check disk space
   - Verify write permissions
   - Validate COMPUTERNAME environment variable

## Support

For issues and feature requests, please contact:
- Original Author: Tuan Hoang
- Maintainer: Mainul Hossain