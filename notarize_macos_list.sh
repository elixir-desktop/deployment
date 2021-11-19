#!/bin/bash
xcrun altool --notarization-history 0 \
               --username "dominic.letz@berlin.de" \
               --password "@env:AC_PASSWORD" \
               --team 4PN2DP4655

# Check status: 
# 
# xcrun altool --notarization-info $UUID -u "dominic.letz@berlin.de" -p @env:AC_PASSWORD
#
