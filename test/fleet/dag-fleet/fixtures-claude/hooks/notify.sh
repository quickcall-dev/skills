#!/usr/bin/env bash
# on_complete_hook target for completion-fleet.json fixture.
# Touches a sentinel file in the fleet root so scenario J can assert the hook fired.
touch "${FLEET_ROOT}/.hook-fired"
