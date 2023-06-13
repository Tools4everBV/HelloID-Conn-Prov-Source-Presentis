
# HelloID-Conn-Prov-Source-Presentis
> :warning: <b> This connector is not tested with HelloID or with a Presentis environment! </b>><br>
:warning: <b> Note that this connector is "a work in progress" and therefore not ready to use in your production environment.

| :information_source: Information |
|:---------------------------|

| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/presentis-logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Source-Presentis_ is a _source_ connector. Presentis provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint     | Description |
| ./schoollocaties | ophalen van alle schoollocaties |
| ./leerlingen?schoollocatie=     | students (leerlingen) per locatie   |
| ./klassen?schoollocatie=        | classes per locatie   |
| ./leerlingklassen?leerlingid    | classes per student (leerling)   |
| ./leerlingen?schoollocatie=     | students per locatie   |
| ./personen?schoollocatie=       | persons per locatie   |



## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| ClientId     | The ClientId to connect to the API | Yes         |
| ClientSecret | The Clientsecret to connect to the API | Yes         |
| Environment  | radio butten to choose test of production environment   | Yes         |
| IsDebug      | The URL to the API                 | Yes         |

### Prerequisites

No special requirements

### Remarks
- persons.ps1 contains the code for collecting general persons
- students.ps1 contains the code for collecting the studends.

- "In"- and "uitschrijfdatum" determine the primary contract of the student
ContractType    = "inschrijving"
 "Schoollocatie" (naam + id) is available on all contracts of this type

- "Klassen"  for each "klas" of an student there is a separate contract on the student
ContractType    = "klas"
"Schoollocatie" (naam + id) is available on all contracts of this type

 "Cursussen" for each course of a student there is a separate contract
 ContractType    = "cursus"
"Schoollocatie" is not available of contracts of this type


## Setup the connector

> no special requirements, the source mapping given is only a default example, and will need to be changed as required.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012557600-Configure-a-custom-PowerShell-source-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
