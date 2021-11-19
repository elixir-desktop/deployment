#!/bin/bash
xcrun altool --notarization-info $1 \
               --username "dominic.letz@berlin.de" \
               --password "@env:AC_PASSWORD"

