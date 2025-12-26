# Centurion 🏛️

A Go-based TUI (Text User Interface) for managing `systemd` services.

**Centurion** provides an interactive, terminal-based interface for `systemctl`, making it easier to visualize the status of services, perform common actions, and view logs without remembering complex command-line flags.

It is named **Centurion** because it commands system "units".

## ✨ Features

- **Service Explorer**: View all systemd services in a scrollable list.
- **Color-Coded Status**: Instantly identify the state of services (e.g., `active`, `failed`, `inactive`) with icons.
- **Core Controls**: Start, stop, and restart services with keyboard shortcuts.
- **Detailed Inspection**: View the full `systemctl status` output for any selected service.
- **Log Viewing**: View recent `journalctl` logs for a service directly within the UI, with filtering capabilities.
- **Search & Filter**: Quickly find services by name.

## Getting Started

### Installation

1. Clone the repo:

    ```sh
    git clone https://github.com/iamdanielv/utils.git
    cd utils/centurion
    ```

2. Build the binary using the Makefile:

    ```sh
    make build
    ```

    This will create the `centurion` binary in the `bin/` directory.

### 🔧 Building with Docker

If you don't want to install Go locally, you can build the binary inside a Docker container. The image is a builder-only image; after building, the resulting binary is copied to `bin/` so you can run it on your host machine.

```sh
# Build the image and extract the binary to ./bin/centurion
make docker-build

# Run the binary on your host
./bin/centurion
```

Note: the Docker image is used only as a build environment. To manage systemd services the binary must be run on the host (it needs access to systemd and journalctl).
3. Run the application:

    ```sh
    ./bin/centurion
    ```

## ⌨️ Keybindings

### Main List

| Key       | Action                       |
| :-------- | :----------------------      |
| `↑`/`k`   | Move Up                      |
| `↓`/`j`   | Move Down                    |
| `home`/`g`| Go to Top                    |
| `end`/`G` | Go to Bottom                 |
| `s`       | **S**tart / **S**top service |
| `r`       | **R**estart selected service |
| `l`       | View service **l**ogs        |
| `enter`   | Inspect service details      |
| `/`       | Filter services              |
| `?`       | Toggle help                  |
| `q`       | **Q**uit                     |

### Log / Details View

| Key       | Action                       |
| :-------- | :----------------------      |
| `↑`/`k`   | Scroll Up                    |
| `↓`/`j`   | Scroll Down                  |
| `home`/`g`| Scroll to Top                |
| `end`/`G` | Scroll to Bottom             |
| `/`       | Filter logs (Log view only)  |
| `esc`/`q` | Close view / Back            |

## 🤝 Contributing

I'm open to and encourage contributions of bug fixes, improvements, and documentation!

## 📜 License

[MIT License](../LICENSE) - See the `LICENSE` file for details.

## 📧 Contact

Let me know if you have any questions or suggestions.

- [Twitter](https://twitter.com/IAmDanielV)
- [BlueSky](https://bsky.app/profile/iamdanielv.bsky.social)
