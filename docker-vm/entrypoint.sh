#!/usr/bin/env bash

/sbin/init

echo "hello entrypoint"

# run the command given as arguments from CMD
exec "$@"
