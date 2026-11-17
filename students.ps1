#####################################################
# HelloID-Conn-Prov-Source-Presentis-Students
#
# Version: 2.0.0
#####################################################
$c = $configuration | ConvertFrom-Json

# Set debug logging
switch ($($c.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

if ($c.Environment -eq "Test") {
    $Script:AuthenticationUri = "https://oauthtest.presentis.nl/oauth2/token"
    $Script:BaseUri = "https://apitest.presentis.nl/rest/v1"
}
else {
    $Script:AuthenticationUri = "https://oauth.presentis.nl/oauth2/token"
    $Script:BaseUri = "https://api.presentis.nl/rest/v1"
}

# Reference date for classes and courses
$referenceDate = (Get-Date).ToUniversalTime().ToString("yyyyMMdd")

#region functions
function Resolve-PresentisError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        Write-Output $httpErrorObj
    }
}

function Invoke-PresentisWebRequestList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [string]
        $ResultProperty
    )
    # The Presentis API uses paging with skip and limit
    $skip = 0
    $limit = 400
    $returnValue = [System.Collections.Generic.List[object]]::new()

    do {
        $splatParams = @{
            Uri         = "$($Uri)skip=$($skip)&limit=$($limit)"
            Method      = 'GET'
            ContentType = 'application/json'
            Headers     = $Script:AuthenticationHeaders
        }
        $result = Invoke-RestMethod @splatParams -Verbose:$false

        $resultCount = 0
        if ($null -ne $result.$ResultProperty) {
            $returnValue.AddRange($result.$ResultProperty)
            $resultCount = @($result.$ResultProperty).Count
        }
        $skip += $limit
    } while ($resultCount -eq $limit)

    Write-Verbose "Successfully queried data from '$($Uri)'. Result count: $($returnValue.Count)"

    return $returnValue
}

function Add-PrefixedProperties {
    # Adds all properties of the source object to the target object, prefixed with the given prefix
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $Target,

        [Parameter(Mandatory)]
        [object]
        $Source,

        [Parameter(Mandatory)]
        [string]
        $Prefix
    )
    foreach ($property in $Source.PsObject.Properties) {
        $Target | Add-Member -MemberType NoteProperty -Name ($Prefix + $property.Name) -Value $property.Value -Force
    }
}
#endregion functions

Write-Information "Starting student import. Base URI: $($Script:BaseUri)"

# Create access token
try {
    $actionMessage = "creating access token at [$($Script:AuthenticationUri)]"

    $splatAccessTokenParams = @{
        Uri     = $Script:AuthenticationUri
        Method  = 'POST'
        Headers = @{
            'content-type'  = 'application/json'
            'grant_type'    = 'CLIENT_CREDENTIALS'
            'client_id'     = $c.ClientId
            'client_secret' = $c.ClientSecret
        }
    }
    $accessToken = Invoke-RestMethod @splatAccessTokenParams -Verbose:$false

    # Presentis returns the token as 'acces_token'
    if ([string]::IsNullOrEmpty($accessToken.acces_token)) {
        throw "No access token returned. Please check the ClientId (including curly brackets) and ClientSecret"
    }

    $Script:AuthenticationHeaders = @{
        Authorization = "Bearer $($accessToken.acces_token)"
    }

    Write-Information "Successfully created access token"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PresentisError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    throw $auditMessage
}

# Query schoollocaties
try {
    $actionMessage = "querying schoollocaties at [$($Script:BaseUri)/schoollocaties]"

    $schoollocatiesList = Invoke-PresentisWebRequestList -Uri "$($Script:BaseUri)/schoollocaties?" -ResultProperty "schoollocaties"

    # Group by schoollocatieid
    $schoollocatiesGrouped = $schoollocatiesList | Group-Object schoollocatieid -AsHashTable -AsString

    Write-Information "Successfully queried schoollocaties. Result: $(@($schoollocatiesList).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PresentisError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    throw $auditMessage
}

# Query cursussen
try {
    $actionMessage = "querying cursussen at [$($Script:BaseUri)/cursussen]"

    $cursussenList = Invoke-PresentisWebRequestList -Uri "$($Script:BaseUri)/cursussen?" -ResultProperty "cursussen"

    # Group by cursusid
    $cursussenGrouped = $cursussenList | Group-Object cursusid -AsHashTable -AsString

    Write-Information "Successfully queried cursussen. Result: $(@($cursussenList).Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PresentisError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    throw $auditMessage
}

# Query klassen, leerlingen, leerlingklassen and leerlingcursussen per schoollocatie
# Classes and courses are queried once per schoollocatie instead of once per student, to prevent a time-out with a large number of students
try {
    $klassenList = [System.Collections.Generic.List[object]]::new()
    $leerlingenList = [System.Collections.Generic.List[object]]::new()
    $leerlingKlassenList = [System.Collections.Generic.List[object]]::new()
    $leerlingCursussenList = [System.Collections.Generic.List[object]]::new()

    foreach ($schoollocatie in $schoollocatiesList) {
        $schoollocatieId = $schoollocatie.schoollocatieid

        $actionMessage = "querying klassen at [$($Script:BaseUri)/klassen] for schoollocatie [$($schoollocatieId)]"
        $klassen = Invoke-PresentisWebRequestList -Uri "$($Script:BaseUri)/klassen?schoollocatie=$($schoollocatieId)&" -ResultProperty "klassen"
        if ($null -ne $klassen) {
            # Add schoollocatieid as linking key, the same klas can exist at multiple schoollocaties
            $klassen | Add-Member -MemberType NoteProperty -Name "schoollocatieid" -Value $schoollocatieId -Force
            $klassenList.AddRange(@($klassen))
        }

        $actionMessage = "querying leerlingen at [$($Script:BaseUri)/leerlingen] for schoollocatie [$($schoollocatieId)]"
        $leerlingen = Invoke-PresentisWebRequestList -Uri "$($Script:BaseUri)/leerlingen?schoollocatie=$($schoollocatieId)&" -ResultProperty "leerlingen"
        if ($null -ne $leerlingen) {
            # Add schoollocatieid as linking key, a leerling can be enrolled at multiple schoollocaties
            $leerlingen | Add-Member -MemberType NoteProperty -Name "schoollocatieid" -Value $schoollocatieId -Force
            $leerlingenList.AddRange(@($leerlingen))
        }

        $actionMessage = "querying leerlingklassen at [$($Script:BaseUri)/leerlingklassen] for schoollocatie [$($schoollocatieId)]"
        $leerlingKlassen = Invoke-PresentisWebRequestList -Uri "$($Script:BaseUri)/leerlingklassen?schoollocatie=$($schoollocatieId)&peildatum=$($referenceDate)&" -ResultProperty "leerlingklassen"
        if ($null -ne $leerlingKlassen) {
            $leerlingKlassen | Add-Member -MemberType NoteProperty -Name "schoollocatieid" -Value $schoollocatieId -Force
            $leerlingKlassenList.AddRange(@($leerlingKlassen))
        }

        $actionMessage = "querying leerlingcursussen at [$($Script:BaseUri)/leerlingcursussen] for schoollocatie [$($schoollocatieId)]"
        $leerlingCursussen = Invoke-PresentisWebRequestList -Uri "$($Script:BaseUri)/leerlingcursussen?schoollocatie=$($schoollocatieId)&peildatum=$($referenceDate)&" -ResultProperty "leerlingcursussen"
        if ($null -ne $leerlingCursussen) {
            $leerlingCursussenList.AddRange(@($leerlingCursussen))
        }
    }

    # Group klassen by schoollocatieid + klas
    $klassenGrouped = $klassenList | Group-Object { "$($_.schoollocatieid)_$($_.klas)" } -AsHashTable -AsString

    # Make sure persons are unique, a leerling enrolled at multiple schoollocaties is returned for each schoollocatie
    $persons = $leerlingenList | Where-Object { $null -ne $_.leerlingid } | Sort-Object leerlingid -Unique

    # Group enrollments (leerlingen per schoollocatie) by leerlingid
    $leerlingenGrouped = $leerlingenList | Where-Object { $null -ne $_.leerlingid } | Group-Object leerlingid -AsHashTable -AsString

    # Make sure leerlingklassen and leerlingcursussen are unique and group by leerlingid
    $leerlingKlassenGrouped = $leerlingKlassenList | Sort-Object leerlingklasid -Unique | Group-Object leerlingid -AsHashTable -AsString
    $leerlingCursussenGrouped = $leerlingCursussenList | Sort-Object leerlingcursusid -Unique | Group-Object leerlingid -AsHashTable -AsString

    Write-Information "Successfully queried klassen. Result: $($klassenList.Count)"
    Write-Information "Successfully queried leerlingen. Result: $(@($persons).Count) unique of $($leerlingenList.Count) enrollments"
    Write-Information "Successfully queried leerlingklassen. Result: $($leerlingKlassenList.Count)"
    Write-Information "Successfully queried leerlingcursussen. Result: $($leerlingCursussenList.Count)"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PresentisError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    throw $auditMessage
}

try {
    $actionMessage = "enhancing and exporting person objects to HelloID"

    # Set counter to keep track of actual exported person objects
    $exportedPersons = 0

    # Enhance the persons model with required properties
    $persons | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "DisplayName" -Value $null -Force
    $persons | Add-Member -MemberType NoteProperty -Name "Contracts" -Value $null -Force

    $persons | ForEach-Object {
        # Set required fields for HelloID
        $_.ExternalId = "$($_.leerlingid)"
        $_.DisplayName = "$("$($_.voornaam) $($_.achternaam)".Trim()) ($($_.ExternalId))"

        $contractsList = [System.Collections.Generic.List[object]]::new()

        # Create contract object(s) based on enrollments, linking key is leerlingid
        $enrollments = $null
        if ($null -ne $leerlingenGrouped) {
            $enrollments = $leerlingenGrouped["$($_.leerlingid)"]
        }
        if ($null -ne $enrollments) {
            foreach ($enrollment in $enrollments) {
                $enrollmentObject = [PSCustomObject]@{
                    ExternalId      = "inschrijving-$($enrollment.leerlingid)-$($enrollment.schoollocatieid)"
                    ContractType    = "inschrijving"
                    leerlingid      = $enrollment.leerlingid
                    schoollocatieid = $enrollment.schoollocatieid
                    inschrijfdatum  = $enrollment.inschrijfdatum
                    uitschrijfdatum = $enrollment.uitschrijfdatum
                }

                # Enhance enrollment with schoollocatie for extra information, such as: omschrijving
                $schoollocatie = $null
                if ($null -ne $schoollocatiesGrouped) {
                    $schoollocatie = $schoollocatiesGrouped["$($enrollment.schoollocatieid)"]
                }
                if ($null -ne $schoollocatie) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $schoollocatie = $schoollocatie | Select-Object -First 1
                    Add-PrefixedProperties -Target $enrollmentObject -Source $schoollocatie -Prefix "schoollocatie_"
                }

                $contractsList.Add($enrollmentObject)
            }
        }

        # Create contract object(s) based on leerlingklassen, linking key is leerlingid
        $leerlingKlassen = $null
        if ($null -ne $leerlingKlassenGrouped) {
            $leerlingKlassen = $leerlingKlassenGrouped["$($_.leerlingid)"]
        }
        if ($null -ne $leerlingKlassen) {
            foreach ($leerlingKlas in $leerlingKlassen) {
                $leerlingKlas | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value "klas-$($leerlingKlas.leerlingklasid)" -Force
                $leerlingKlas | Add-Member -MemberType NoteProperty -Name "ContractType" -Value "klas" -Force

                # Enhance leerlingklas with klas for extra information, such as: omschrijving
                $klas = $null
                if ($null -ne $klassenGrouped) {
                    $klas = $klassenGrouped["$($leerlingKlas.schoollocatieid)_$($leerlingKlas.klas)"]
                }
                if ($null -ne $klas) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $klas = $klas | Select-Object -First 1
                    Add-PrefixedProperties -Target $leerlingKlas -Source $klas -Prefix "klas_"
                }
                else {
                    ### Be very careful when logging in a loop, only use this when the amount is below 100
                    ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                    # Write-Warning "No klas found for leerlingklas: $($leerlingKlas.leerlingklasid)"
                }

                # Enhance leerlingklas with schoollocatie for extra information, such as: omschrijving
                $schoollocatie = $null
                if ($null -ne $schoollocatiesGrouped) {
                    $schoollocatie = $schoollocatiesGrouped["$($leerlingKlas.schoollocatieid)"]
                }
                if ($null -ne $schoollocatie) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $schoollocatie = $schoollocatie | Select-Object -First 1
                    Add-PrefixedProperties -Target $leerlingKlas -Source $schoollocatie -Prefix "schoollocatie_"
                }

                $contractsList.Add($leerlingKlas)
            }
        }

        # Create contract object(s) based on leerlingcursussen, linking key is leerlingid
        $leerlingCursussen = $null
        if ($null -ne $leerlingCursussenGrouped) {
            $leerlingCursussen = $leerlingCursussenGrouped["$($_.leerlingid)"]
        }
        if ($null -ne $leerlingCursussen) {
            foreach ($leerlingCursus in $leerlingCursussen) {
                $leerlingCursus | Add-Member -MemberType NoteProperty -Name "ExternalId" -Value "cursus-$($leerlingCursus.leerlingcursusid)" -Force
                $leerlingCursus | Add-Member -MemberType NoteProperty -Name "ContractType" -Value "cursus" -Force

                # Enhance leerlingcursus with cursus for extra information, such as: omschrijving
                $cursus = $null
                if ($null -ne $cursussenGrouped) {
                    $cursus = $cursussenGrouped["$($leerlingCursus.cursusid)"]
                }
                if ($null -ne $cursus) {
                    # In case multiple are found with the same ID, we always select the first one in the array
                    $cursus = $cursus | Select-Object -First 1
                    Add-PrefixedProperties -Target $leerlingCursus -Source $cursus -Prefix "cursus_"
                }
                else {
                    ### Be very careful when logging in a loop, only use this when the amount is below 100
                    ### When this would log over 100 lines, please refer from using this in HelloID and troubleshoot this in local PS
                    # Write-Warning "No cursus found for leerlingcursus: $($leerlingCursus.leerlingcursusid)"
                }

                $contractsList.Add($leerlingCursus)
            }
        }

        # Add Contracts to person
        $_.Contracts = $contractsList

        # Remove schoollocatieid from person (after creating the contracts, the person is also one of the enrollments)
        # A leerling can be enrolled at multiple schoollocaties, the schoollocatie is available on the contracts
        $_.PSObject.Properties.Remove('schoollocatieid')

        # Sanitize and export the json
        $person = $_ | ConvertTo-Json -Depth 10
        $person = $person.Replace("._", "__")

        Write-Output $person

        # Updated counter to keep track of actual exported person objects
        $exportedPersons++
    }

    Write-Information "Successfully enhanced and exported person objects to HelloID. Result count: $($exportedPersons)"
    Write-Information "Student import completed"
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-PresentisError -ErrorObject $ex
        $auditMessage = "Error $($actionMessage). Error: $($errorObj.FriendlyMessage)"
        $warningMessage = "Error at Line [$($errorObj.ScriptLineNumber)]: $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Error $($actionMessage). Error: $($ex.Exception.Message)"
        $warningMessage = "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }

    Write-Warning $warningMessage

    throw $auditMessage
}
