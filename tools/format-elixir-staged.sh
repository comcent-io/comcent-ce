#!/bin/bash

# Formats only the staged Elixir files passed in as arguments (invoked by
# lint-staged with absolute paths). Runs from server/ so mix picks up
# server/.formatter.exs and server/mix.exs. lint-staged re-stages whatever
# this script modifies, so formatting fixes never end up as a dangling
# unstaged diff, and files outside this commit are never touched.

set -e

cd "$(dirname "$0")/../server"
mix format "$@"
