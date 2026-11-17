# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [2.0.0] - 2026-11-17

### Breaking changes
- Contracts now have a unique `ExternalId` (`inschrijving-<leerlingid>-<schoollocatieid>`, `klas-<leerlingklasid>`, `cursus-<leerlingcursusid>`). Existing contracts in HelloID will be replaced by contracts with the new `ExternalId`.
- Related data on the contracts is now available as prefixed fields: `schoollocatieOmschrijving` is replaced by `schoollocatie_omschrijving`, `klasomschrijving` by `klas_omschrijving` and `cursusomschrijving` by `cursus_omschrijving`. `schoollocatieId` is replaced by `schoollocatieid`.
- The person-level fields `SchoollocatieId` and `SchoollocatieOmschrijving` are removed. A student can be enrolled at multiple school locations; the school location is available on the contracts.
- `DisplayName` now includes the `ExternalId`: `<voornaam> <achternaam> (<leerlingid>)`.
- The source mapping must be updated to the new `mapping.json`.

### Added
- `CHANGELOG.md` to document all notable changes going forward.
- `klas` and `cursus` contracts contain all fields returned by Presentis (e.g. `iltcode`, `leerjaar`, `schooljaar`).
- Students enrolled at multiple school locations are merged into one person, with an `inschrijving` contract per school location.
- Complex mappings for `StartDate` and `EndDate` that convert the Presentis `yyyyMMdd` dates per `ContractType`. An empty date or `00000000` results in an empty date.
- Mapping for `Department` (school location), `Title` (class or course, with fallback on the code when the description is empty) and `Type` (`ContractType`).

### Changed
- `leerlingklassen` and `leerlingcursussen` are retrieved once per school location instead of once per student, to prevent a time-out of the import with a large number of students.
- Structure, logging and error handling of `students.ps1` aligned with the other source connectors: all data is queried first (one try/catch per source), then the persons are enhanced and exported.
- Errors now stop the import (`throw`) instead of writing an error and continuing.
- Description of the `ClientId` configuration field: the client ID must include the curly brackets.
- Readme updated with the endpoints, contracts, mapping and remarks.

### Known limitations
- `persons.ps1` is not updated yet.

## [1.0.0] - 2023-01-27

### Added
- Initial connector (`students.ps1` and `persons.ps1`).

### Fixed (2024-05-06)
- Use the `acces_token` property of the token response and the result property of the API responses for data retrieval.
