#!/bin/sh
echo "* 02-test-seq here"
CHECK_ME=$(cat /tmp/check-me)
if [ "$CHECK_ME" != "$CUSTOM_GALETTE" ]; then
  echo "sequential script test failed"
  exit 1
else 
  echo "sequential script test succeeded"
fi
