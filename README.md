# MacLatency

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-15+-blue)](https://github.com/jmaddington/maclatency)
[![Swift](https://img.shields.io/badge/Swift-6-orange)](https://swift.org)

A lightweight macOS menu bar app that monitors network latency to your gateway and custom hosts. See at a glance if your network is healthy.

![screenshot](./assets/screenshot.png)

## Background

I've wanted an app like this for years, but didn't want to learn Swift to make it happen. With the advent of LLMs, I finally have my application.

[NirSoft's PingInfoView](https://www.nirsoft.net/utils/multiple_ping_tool.html) was what I wanted on Windows, but this new app is even closer to what I need on my Mac - a simple menu bar indicator showing network health at a glance.

This project started as a fork of [MacThrottle](https://github.com/angristan/MacThrottle) by angristan, which was a thermal monitoring app. I used [Claude Code](https://claude.ai/claude-code) and GPT-5 (via Xcode) to transform it into a network latency monitor.

## Features

- Displays network latency status in the menu bar with color-coded icons
- Auto-discovers and monitors your network gateway(s)
- Add custom hosts to monitor (IP addresses or hostnames)
- History graph showing latency over the last 10 minutes
- Statistics showing time spent in each latency state
- Configurable latency thresholds (default: <50ms excellent, <100ms good, <200ms fair)
- Configurable poll interval (1-30 seconds)
- Notifications for:
  - Poor latency (>200ms by default)
  - Host offline/unreachable
  - Recovery to good status
  - Optional notification sounds
- Launch at Login option
- No admin privileges required

## Latency States

| Color  | State     | Default Threshold |
| ------ | --------- | ----------------- |
| Green  | Excellent | < 50ms            |
| Yellow | Good      | 50-100ms          |
| Orange | Fair      | 100-200ms         |
| Red    | Poor      | > 200ms           |
| Red    | Offline   | Timeout           |

## Installation

Since the app is not signed, Gatekeeper may block it on first launch. You can build it locally with Xcode to sign it with your own certificate.

### Build Locally

Building locally automatically signs the app with your development certificate, avoiding Gatekeeper issues.

```bash
# Clone the repo
git clone https://github.com/jmaddington/maclatency.git
cd maclatency

# Build with Xcode
xcodebuild -project MacThrottle.xcodeproj \
  -scheme MacThrottle \
  -configuration Release \
  -derivedDataPath build

# Run the app
open build/Build/Products/Release/MacThrottle.app
```

Or open `MacThrottle.xcodeproj` in Xcode and press `Cmd+R` to build and run.

## How It Works

### Latency Monitoring

MacLatency uses ICMP ping to measure round-trip time to monitored hosts. It automatically discovers your network gateway(s) by querying the system routing table, and you can add additional hosts to monitor.

The app polls all enabled hosts at a configurable interval (default: 5 seconds) and displays the worst latency in the menu bar. Individual host latencies are shown in the dropdown menu.

### Gateway Discovery

On startup and when you click "Refresh", the app discovers active network interfaces and their default gateways using the system routing table. This allows it to monitor your actual network path rather than just an arbitrary external server.

## Requirements

- macOS 15.0+ (Sequoia)

## Credits

- Original [MacThrottle](https://github.com/angristan/MacThrottle) by [angristan](https://github.com/angristan)
- Transformed to latency monitor using [Claude Code](https://claude.ai/claude-code) and GPT-5

## License

MIT License - see [LICENSE](LICENSE) for details.
