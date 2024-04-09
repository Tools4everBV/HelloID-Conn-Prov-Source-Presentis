########################################################################
# HelloID-Conn-Prov-Source-Presentis-Persons
#
# Version: 1.0.0
########################################################################
# Initialize default value's
$config = $Configuration | ConvertFrom-Json

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Invoke-PresentisRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory = $false)]  
        [string]
        $ResultProperty
    )
    $skip = 0
    $limit = 400
    [bool]$done = $false

    $totalResultList = [System.Collections.Generic.List[object]]::new()

    try {
        Write-Verbose "Invoking command '$($MyInvocation.MyCommand)' to endpoint '$Uri'"
        while($true)
        {
            $splatParams = @{
                Uri         = $Uri +"skip=$skip&limit=$limit"
                Method      = 'Get'
                ContentType = 'application/json'
                Headers     =  $Headers
            }
            $resultlist = Invoke-RestMethod @splatParams -Verbose:$false
            if ($null -ne $resultList.$ResultProperty)  {
                $totalResultList.AddRange($resultlist.$ResultProperty)
                if ($resultList.$ResultProperty.Count -eq $limit) {
                    $skip += $limit
                    continue
                }
            }
            break;
        }
        write-output $totalResultList
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-PresentisError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ExceptionObject
    )

    $httpErrorObj = [PSCustomObject]@{
        ScriptLineNumber = $ExceptionObject.InvocationInfo.ScriptLineNumber
        Line             = $ExceptionObject.InvocationInfo.Line
        ErrorDetails     = $ExceptionObject.Exception.Message
        FriendlyMessage  = $ExceptionObject.Exception.Message
    }
    if (($null -eq $ExceptionObject.ErrorDetails) -or ([string]::IsNullOrWhiteSpace($ExceptionObject.ErrorDetails.Message))) {
        if ($null -ne $ExceptionObject.Exception.Response) {
            $responseStream = [System.IO.StreamReader]::new($ExceptionObject.Exception.Response.GetResponseStream())
            if ($null -ne $responseStream) {
                $httpErrorObj.ErrorDetails = $responseStream.ReadToEnd()
            }
        }
    }
    else {
        $httpErrorObj.ErrorDetails = $ExceptionObject.ErrorDetails.Message
    }

    Write-Output $httpErrorObj

}
#endregion

try {

    $now = (Get-Date).ToUniversalTime()
    $dateFormat ="yyyyMMdd"
    $nowString = $now.ToString($dateFormat)

    if ($config.Environment -eq "Test")
    {
        $OAuthUrl = "https://oauthtest.presentis.nl/oauth2/token"
        $BaseUrl =  "https://apitest.presentis.nl/rest/v1"
    }
    else {
        $OAuthUrl = "https://oauth.presentis.nl/oauth2/token"
        $BaseUrl = "https://api.presentis.nl/rest/v1"
    }

    Write-Verbose "Retrieve OAuth token"
    $headers = @{
        'content-type'  = 'application/json'
        'grant_type'    = 'CLIENT_CREDENTIALS'
        'client_id'     = $($config.ClientID)
        'client_secret' = $($config.ClientSecret)
    }
    $splatOauthParams = @{
        Uri         =  $OAuthUrl
        Method      = 'POST'
        Headers     =  $Headers
    }

    $responseToken = Invoke-RestMethod @splatOauthParams -Verbose:$false

    #get lookuplist for cursus
    $cursusResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/cursussen?" -Headers  @{Authorization = "Bearer $($responseToken.acces_token)"} -ResultProperty "cursussen"
    $cursusLookup =  $cursusResult | group-object -Property "cursusid" -AsHashTable

    $schoollocatiesResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/schoollocaties?" -Headers  @{Authorization = "Bearer $($responseToken.acces_token)"} -ResultProperty "schoollocaties"

    foreach ($Schoollocatie in $schoollocatiesResult)
    {
        $LeerlingenResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/leerlingen?schoollocatie=$($schoollocatie.schoollocatieid)&" -Headers  @{Authorization = "Bearer $($responseToken.acces_token)"} -ResultProperty "leerlingen"
        foreach ($Leerling in $LeerlingenResult)
        {
            $Leerling | Add-Member -NotePropertyMembers @{ ExternalId = $leerling.leerlingid }
            $Leerling | Add-Member -NotePropertyMembers @{ DisplayName = "$($leerling.voornaam) $($leerling.achternaam)".trim(' ') }
            $Leerling | Add-Member -NotePropertyMembers @{ SchoollocatieId = $Schoollocatie.schoollocatieid} -Force
            $Leerling | Add-Member -NotePropertyMembers @{ SchoollocatieOmschrijving = $Schoollocatie.omschrijving}
            $Leerling | Add-Member -NotePropertyMembers @{ Contracts = [System.Collections.Generic.List[Object]]::new() }
            #inschrijving
            $primaryContract = @{
                ContractType    = "inschrijving"
                inschrijfdatum  = $Leerling.inschrijfdatum
                uitschrijfdatum = $Leerling.uitschrijfdatum
                schoollocatieId   = $Leerling.schoollocatieId
                schoollocatieOmschrijving   = $Leerling.schoollocatieOmschrijving
            }
            $leerling.Contracts.add($primaryContract)
            # klassen
            $klassenResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/klassen?schoollocatie=$($schoollocatie.schoollocatieid)&" -Headers  @{Authorization = "Bearer $($responseToken.acces_token)"} -ResultProperty "klassen"
            $klassenLookup =  $klassenResult | group-object -Property "klas" -AsHashTable

            $LeerlingKlassenResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/leerlingklassen?leerlingid=$($leerling.leerlingid)&peildatum=$nowString&" -Headers  @{Authorization = "Bearer $($responseToken.acces_token)"} -ResultProperty "leerlingklassen"
            foreach ($klas in  $LeerlingKlassenResult)
            {
                $klasContract = @{
                    ContractType    = "klas"
                    klas = $klas.klas
                    klasomschrijving =  $klassenLookup[$klas.klas].omschrijving
                    leerlingklasid = $klas.leerlingklasid
                    mentor1id = $klas.mentor1id
                    mentor2id = $klas.mentor2id
                    inschrijfdatum  = $klas.inschrijfdatum
                    uitschrijfdatum = $klas.uitschrijfdatum
                    begindatum = $klas.begindatum
                    einddatum = $klas.einddatum
                    gast = $klas.gast
                    schoollocatieId   = $Leerling.schoollocatieId
                    schoollocatieOmschrijving   = $Leerling.schoollocatieOmschrijving
                }
                $leerling.Contracts.add($klasContract)
            }

            #Cursussen
            $LeerlingCursussenResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/leerlingcursussen?leerlingid=$($leerling.leerlingid)&peildatum=$nowString&" -Headers  @{Authorization = "Bearer $($responseToken.acces_token)"} -ResultProperty "leerlingcursussen"
            foreach ($cursus in  $LeerlingCursussenResult)
            {
                $cursusContract = @{
                    ContractType    = "cursus"
                    leerlingcursusid = $cursus.leerlingcursusid
                    cursusid        = $cursus.cursusid
                    cursusomschrijving =  $cursusLookup[$cursus.cursusid].omschrijving
                    begindatum      = $cursus.begindatum
                    einddatum     = $cursus.einddatum
                }
                $leerling.Contracts.add($cursusContract)
            }

            Write-Output $Leerling | ConvertTo-Json -Depth 10
        }
    }
}
catch {
    $ex = $PSItem
    $errorObj = Resolve-PresentisError -ExceptionObject $ex
    Write-Verbose "Could not import Presentis students. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    Write-Error "Could not import Presentis students. Error: $($errorObj.FriendlyMessage)"
}