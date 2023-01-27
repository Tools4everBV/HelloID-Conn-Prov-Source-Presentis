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
        $Headers
    )
    $skip = 0
    $limit = 400

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
            if ($null -ne $resultList)  {
                $totalResultList.AddRange($resultlist)
                if ($resultList.Count -eq $limit) {
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

    if ($config.Environment -eq "Test")
    {
        $OAuthUrl = https://oauthtest.presentis.nl/oauth2/token
        $BaseUrl =  https://apitest.presentis.nl/rest/v1
    }
    else {
        $OAuthUrl = https://oauth.presentis.nl/oauth2/token
        $BaseUrl = https://api.presentis.nl/rest/v1
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

    Write-Verbose 'Collecting list of "schoollocaties"'

    $schoollocatiesResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/schoollocaties?" -Headers  @{Authorization = "Bearer $($responseToken.token)"}

    Write-Verbose 'Collecting Persons and importing raw data in HelloID'

    foreach ($Schoollocatie in $schoollocatiesResult)
    {
        $personenResult = Invoke-PresentisRestMethod -Uri "$BaseUrl/personen?schoollocatie=$($schoollocatie.schoollocatieid)&" -Headers  @{Authorization = "Bearer $($responseToken.token)"}
        foreach ($person in $personenResult ) {
            $person | Add-Member -NotePropertyMembers @{ ExternalId = $person.persoonid }
            $person | Add-Member -NotePropertyMembers @{ DisplayName = "$($person.voornaam) $($person.achternaam)".trim(' ') }
            $person | Add-Member -NotePropertyMembers @{ SchoollocatieId = $Schoollocatie.schoollocatieid}
            $person | Add-Member -NotePropertyMembers @{ SchoollocatieOmschrijving = $Schoollocatie.omschrijving}
            Write-Output $person | ConvertTo-Json -Depth 10
        }
    }
} catch {
    $ex = $PSItem
    $errorObj = Resolve-PresentisError -ExceptionObject $ex
    Write-Verbose "Could not import Presentis persons. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    throw "Could not import Presentis persons. Error: $($errorObj.FriendlyMessage)"
}
