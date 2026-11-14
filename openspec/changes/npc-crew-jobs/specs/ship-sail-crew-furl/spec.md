# ship-sail-crew-furl Specification

## Purpose

Per-sail crew furl request on the pinnace rig, with the existing storm auto-furl kept as fallback (ship-side hook, our agents, slice H2). Verified by `--weather=storm` logs.

## Requirements

### Requirement: Per-sail furl request

The rig SHALL expose `request_furl(idx, t)` where idx is the sail index and t in [0,1] the target furl amount. Requests SHALL be honoured by animating the sail to t. The API SHALL be optional: ship behaviour SHALL be valid without any caller.

#### Scenario: Request honoured
- GIVEN calm sails fully set
- WHEN `request_furl(1, 1.0)` is called
- THEN sail 1 SHALL animate to fully furled and the log SHALL show `furl_request idx=1 t=1.0` then `furl_done idx=1`
- AND other sails SHALL be unaffected

#### Scenario: Partial reef
- GIVEN a sail set
- WHEN `request_furl(0, 0.5)` is called
- THEN sail 0 SHALL reach 0.5 +- 0.02

#### Scenario: Invalid index
- GIVEN a ship with S sails
- WHEN `request_furl(S, 1.0)` is called
- THEN the call SHALL be ignored with one warning and no script error

#### Scenario: Value clamping
- GIVEN any sail
- WHEN `request_furl(0, 1.7)` is called
- THEN t SHALL be clamped to 1.0

### Requirement: Storm auto-furl fallback

The existing auto-furl at storm intensity > 0.86 SHALL remain, applying only to sails not already furled or being furled by a request.

#### Scenario: Fallback fires
- GIVEN `--weather=storm` and no crew requests
- WHEN storm intensity exceeds 0.86
- THEN all sails SHALL auto-furl and the log SHALL mark `furl_source=auto`

#### Scenario: Crew requests pre-empt
- GIVEN crew requests furl for all sails before storm reaches 0.86
- WHEN the storm exceeds 0.86
- THEN logs SHALL show `furl_source=crew` for each sail and no `auto` event

#### Scenario: Partial crew coverage
- GIVEN crew furled 2 of 4 sails at 0.86
- WHEN the threshold passes
- THEN only the remaining 2 SHALL auto-furl

### Requirement: Un-furl and state exposure

`request_furl(idx, 0.0)` SHALL set a sail again, and the per-sail furl state SHALL be queryable for the NPC session and logs. Auto-furl SHALL release when the storm subsides per existing behaviour.

#### Scenario: Re-set
- GIVEN a furled sail and calm weather
- WHEN `request_furl(idx, 0.0)` is called
- THEN the sail SHALL return to set state
