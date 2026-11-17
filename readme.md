# HelloID-Conn-Prov-Source-Presentis

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible for acquiring the connection details such as client ID and client secret. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/presentis-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Source-Presentis](#helloid-conn-prov-source-presentis)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Source-Presentis_ is a _source_ connector. Presentis provides a set of REST APIs that allow you to programmatically interact with its data. The connector contains two import scripts:

| Script         | Description                                              |
| -------------- | -------------------------------------------------------- |
| `students.ps1` | Imports students (leerlingen) with their enrollment, classes and courses as contracts. |
| `persons.ps1`  | Imports general persons (personen), for example staff.   |

The connector uses the API endpoints listed below. All list endpoints are paged with `skip` and `limit` (400 records per page).

| Endpoint                                         | Used in        | Description                                    |
| ------------------------------------------------ | -------------- | ---------------------------------------------- |
| `/schoollocaties`                                | both           | All school locations                           |
| `/leerlingen?schoollocatie=`                     | `students.ps1` | Students per school location                   |
| `/klassen?schoollocatie=`                        | `students.ps1` | Classes per school location (lookup for class descriptions) |
| `/cursussen`                                     | `students.ps1` | All courses (lookup for course descriptions)   |
| `/leerlingklassen?schoollocatie=&peildatum=`     | `students.ps1` | Classes of all students per school location on the reference date (today) |
| `/leerlingcursussen?schoollocatie=&peildatum=`   | `students.ps1` | Courses of all students per school location on the reference date (today) |
| `/personen?schoollocatie=`                       | `persons.ps1`  | Persons per school location                    |

The API base URL depends on the selected environment:

| Environment | OAuth URL                                    | API URL                                |
| ----------- | -------------------------------------------- | -------------------------------------- |
| Production  | `https://oauth.presentis.nl/oauth2/token`     | `https://api.presentis.nl/rest/v1`     |
| Test        | `https://oauthtest.presentis.nl/oauth2/token` | `https://apitest.presentis.nl/rest/v1` |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                                            | Mandatory |
| ------------ | ------------------------------------------------------ | --------- |
| ClientId     | The client ID (shown as UserName) to connect to the API, including the curly brackets, e.g. `{00000000-0000-0000-0000-000000000000}` | Yes       |
| ClientSecret | The client secret to connect to the API                | Yes       |
| Environment  | Choose between the production and the test environment | Yes       |
| IsDebug      | When toggled, debug logging will be displayed          | No        |

### Prerequisites

- A client ID and client secret for the Presentis API (OAuth client credentials), with read access to the endpoints listed above.

> [!NOTE]
> Enter the client ID including the curly brackets around the ID, e.g. `{00000000-0000-0000-0000-000000000000}`. Without the brackets the token request fails.

### Remarks

#### Contracts

Each student gets one or more contracts, distinguished by the `ContractType` property. Every contract has a unique `ExternalId`:

| ContractType   | Source               | ExternalId                                    | Description | School location (ID + description) |
| -------------- | -------------------- | --------------------------------------------- | ----------- | ---------------------------------- |
| `inschrijving` | `/leerlingen`        | `inschrijving-<leerlingid>-<schoollocatieid>` | The enrollment of the student at a school location, based on `inschrijfdatum` and `uitschrijfdatum`. Use this as the primary contract. | Yes |
| `klas`         | `/leerlingklassen`   | `klas-<leerlingklasid>`                       | One contract per class of the student, with all fields of the leerlingklas (e.g. `mentor1id`, `mentor2id`, `iltcode`, `leerjaar`, `schooljaar`). | Yes |
| `cursus`       | `/leerlingcursussen` | `cursus-<leerlingcursusid>`                   | One contract per course of the student, with all fields of the leerlingcursus. | No |

The contracts are enhanced with the related objects, prefixed with the name of the object. When the related object is not found, the prefixed fields are not available on the contract:

| Prefix           | Source            | Available on                     | Example                      |
| ---------------- | ----------------- | -------------------------------- | ---------------------------- |
| `schoollocatie_` | `/schoollocaties` | `inschrijving`, `klas`           | `schoollocatie_omschrijving` |
| `klas_`          | `/klassen`        | `klas`                           | `klas_omschrijving`          |
| `cursus_`        | `/cursussen`      | `cursus`                         | `cursus_omschrijving`        |

Presentis returns dates as `yyyyMMdd`. The conversion to a date for HelloID is done in the (complex) source mapping of `StartDate` and `EndDate`, based on the `ContractType`. An empty date or `00000000` results in an empty date in HelloID:

| ContractType   | StartDate        | EndDate           |
| -------------- | ---------------- | ----------------- |
| `inschrijving` | `inschrijfdatum` | `uitschrijfdatum` |
| `klas`         | `begindatum`     | `einddatum`       |
| `cursus`       | `begindatum`     | `einddatum`       |

The `/leerlingklassen` endpoint per school location returns all classes of the school year, including past and future classes. HelloID determines the active contracts based on `StartDate` and `EndDate`.

#### Students at multiple school locations

Students are retrieved per school location. A student enrolled at more than one location is imported as one person, with an `inschrijving` contract for each location. Classes and courses that are returned for more than one location are added only once. The school location is available on the contracts, not on the person.

#### Performance

All data is retrieved first: school locations and courses once, and classes, students, student classes and student courses once per school location. The number of API calls depends on the number of school locations and not on the number of students. Afterwards the persons and contracts are created from this data and exported to HelloID.

#### Mapping

The `mapping.json` contains a basic mapping for `students.ps1`, to be extended with the requirements of the customer:

| HelloID field            | Source                                                                 |
| ------------------------ | ---------------------------------------------------------------------- |
| `ExternalId`             | `leerlingid`                                                           |
| `Name.GivenName`, `Name.NickName` | `voornaam`                                                    |
| `Name.FamilyName`        | `achternaam`                                                           |
| `Name.Convention`        | `B` (fixed)                                                            |
| Contract `ExternalId`    | `ExternalId`                                                           |
| Contract `StartDate` / `EndDate` | `inschrijfdatum` / `uitschrijfdatum` for the enrollment, `begindatum` / `einddatum` for classes and courses, converted from `yyyyMMdd` (complex mapping) |
| `Department`             | `schoollocatieid` / `schoollocatie_omschrijving` (empty for `cursus`)  |
| `Title`                  | `klas` / `klas_omschrijving` for classes, `cursusid` / `cursus_omschrijving` for courses, `Leerling` for the enrollment. When the description is empty, the code is used (complex mapping) |
| `Type.Code` / `Type.Description` | `ContractType`                                                 |

## Setup the connector

1. Add a new source system in HelloID and select the PowerShell connector.
2. Paste the contents of `students.ps1` (or `persons.ps1`) as the person import script.
3. Configure the connection settings using `configuration.json`.
4. Import `mapping.json` and adjust the mapping as required.

For more information on configuring a HelloID PowerShell source system, see the [HelloID documentation](https://docs.helloid.com/en/provisioning/source-systems/powershell-source-systems.html).

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/source-systems/powershell-source-systems.html) pages_.

> [!TIP]
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
