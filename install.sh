#!/usr/bin/env bash

cd "$(dirname "$0")"

echo "Starting fresh install setup..."

./scripts/link.sh
./scripts/system.sh

echo "Setup finished."
