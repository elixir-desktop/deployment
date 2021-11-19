#!/bin/bash
export MIX_ENV=prod
xcrun altool --notarize-app \
               --primary-bundle-id "io.example.app.dmg" \
               --username "@env:USERNAME" \
               --password "@env:AC_PASSWORD" \
               --team 4PN2DP4655 \
               --file _build/${MIX_ENV}/TodoApp-*.dmg

# Check status: 
# 
# xcrun altool --notarization-info $UUID -u "dominic.letz@berlin.de" -p @env:AC_PASSWORD
#