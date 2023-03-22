#!/bin/sh
if [ $1 = '--version' ]; then
  clang --version | sed 's/^Alpine clang version/clang version/'
  exit 0
fi
exec clang $@
