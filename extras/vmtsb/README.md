# vmtsb

## Overview
`vmtsb.sh` is a script designed to help users manage their virtual machine instances. By sourcing this script to your shell, you can easily create a daily cron job that suspends instances under your name.

It is part of the run-tsb-in-vms initiative, documented [here](https://tetrate-internal.atlassian.net/wiki/x/A4DHD).

The owner is the `tetrand_owner` under which the instance was created. See [here](https://github.com/tetrateio/tetrate/blob/master/cloud/docs/gcp/labels.md) 

## Usage
1. **Source the script:**
    ```sh
    source /path/to/vmtsb.sh
    ```
    or add it to your your shell sources path.

2. **Create a daily cron job:**
    Add the following line to your crontab to suspend all your instances daily at a specified time (e.g., 5 PM):
    ```sh
    0 17 * * * /path/to/vmtsb.sh -o <your-tag> -a suspend
    ```

## Functions
```bash
$ vmtsb -h
 Usage:

---VMTSB ---

Manage your VM TSB instances with ease
  -h      Help menu
  -o      Owner tag. See https://github.com/tetrateio/tetrate/blob/master/cloud/docs/gcp/labels.md
  -s      Status (RUNNING|SUSPENDED|TERMINATED)
  -a      Action to perform (resume, suspend, stop, start, delete). Recommended for speed are resume and suspend.

  E.g.:
    Take all ric's machines which are in running state and suspend them
    vmtsb -o ric -s RUNNING -a SUSPEND
```

## Example
To resume all instances, run:
```bash
$ vmtsb -o ric -a resume
```

# Testing

## Prerequisites

This script uses [Bats](https://github.com/bats-core/bats-core) for testing. To install Bats:

### Installation (Linux/macOS)
```sh
git clone https://github.com/bats-core/bats-core.git
cd bats-core
sudo ./install.sh /usr/local
```
Or directly with brew
```
brew install bats-core
```

### Run the tests
Go to `tests` directory and run:

```shell
bats tests-vmtsb.bats

tests-vmtsb.bats
 ✓ Check vmtsb.sh exists and is accessible
 ✓ Test no arguments
 ✓ Test invalid argument
 ✓ Test empty owner argument
 ✓ Test get the help message
 ✓ Test listing all instances
 ✓ Test owner with no action argument
 ✓ Test owner with action argument

8 tests, 0 failures
```

Made with ❤️ in Tetrate
