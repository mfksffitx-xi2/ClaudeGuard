<div align="center">

<img src="程序/icons/app-icon-128.png" width="96" alt="Claude Guard" />

# Claude Guard (Claude守护)

**Checks your PC's network and privacy setup before you use Claude, and closes Claude and your browsers if something is unsafe.**

**For Claude users who want an account-protection / anti-ban style check first (egress IP, DNS, global proxy, location, WebRTC).**

[![Release](https://img.shields.io/github/v/release/mfksffitx-xi2/ClaudeGuard?style=flat-square)](https://github.com/mfksffitx-xi2/ClaudeGuard/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/mfksffitx-xi2/ClaudeGuard/total?style=flat-square)](https://github.com/mfksffitx-xi2/ClaudeGuard/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6?style=flat-square&logo=windows)](#requirements)
[![License](https://img.shields.io/badge/license-non--commercial-red?style=flat-square)](LICENSE)

[简体中文](README.md) | **English**

</div>

> The app UI is in Chinese only.

![Screenshot](docs/screenshot.png)

## Features

- **Checklist**: 17 checks: proxy app, TUN adapter, global mode, egress country, timezone, region format, IPv6, DNS, WebRTC, browser language, location sharing, line type (residential/datacenter), Claude reachability
- **Bodyguard**: while the app runs, closes Claude and browsers if the egress country, proxy state or location sharing becomes unsafe. It's debounced: one failed check never closes anything, and a site that just can't be reached never closes the browser.
- **One-click fix**: timezone, region format, IPv6, location sharing, browser WebRTC hardening, web content language, a firewall rule for WebRTC UDP, and Clash DNS leak protection. You still set TUN, global mode and the node in Clash by hand.
- **Continent → country picker**, or auto-detect from the current egress
- **Runs in the tray**, and **Check for updates** opens the Releases page
- **Bundled browser extension** that makes the browser report English region and font settings (Edge / Chrome)

## Requirements

- Windows 10 / 11
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) (or a compatible Clash client) with a working node
- Edge or Chrome

## Install

1. Download `ClaudeGuard-v<version>.zip` from [Releases](https://github.com/mfksffitx-xi2/ClaudeGuard/releases/latest). Ignore "Source code".
2. Unzip it, then run `安装.bat` (install). No admin needed, and nothing runs at startup.
3. Open **Claude守护** from the desktop. To uninstall, run `卸载.bat`.

## License & disclaimer

**Non-commercial license** ([LICENSE](LICENSE)): personal use, study, modification and free sharing are fine. Selling, paid licensing, or bundling into commercial products or services is not allowed without written permission.

This tool reduces common misconfiguration and leak risks. It does **not** guarantee anonymity or account safety. It is not affiliated with Anthropic.
