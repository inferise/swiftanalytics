# Vendored: Sovran

Source: https://github.com/segmentio/sovran-swift
Version: 1.1.2
Vendored: 2026-08-16

A small state-store / event-subscription library. Local only — it performs no
networking and sends nothing anywhere.

Licensed MIT. `LICENSE` in this directory is the upstream copyright notice and
must be retained: MIT permits us to copy, modify, and redistribute this code
precisely on the condition that the notice travels with it. Its presence is a
license obligation, not a leftover.

## Local modifications

- `Store.swift`: dispatch queue labels changed from `state.update.segment.com`
  and `state.sync.segment.com` to their `inferise.com` equivalents. Labels are
  cosmetic — they surface in debuggers and crash reports.

Upstream fixes are no longer picked up automatically; re-vendor deliberately if
a relevant one lands.
