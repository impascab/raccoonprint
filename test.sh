#!/bin/zsh
# Unit tests. No printer needed.
set -e
cd "$(dirname "$0")"; mkdir -p build
swiftc -swift-version 5 -O -parse-as-library -o build/unit Tests/unit.swift Sources/{Encoder,TextRender,Log,Sender}.swift
build/unit | tee build/unit.txt
grep -q '^failures 0$' build/unit.txt
