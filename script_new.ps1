#Powershell Script to Create and Deploy an Azure App service using powershell

#Declare the environment name before executing the script
$appdirectory="C:\Users\mandarl\Desktop\Publish" #publish files need to be placed on this location or directory
$resouregroupname = "RS-DEV-E-1-API-Lavanya"
$webappname="awdocswebapp1" ########Enter a New name for webapp before executing this scipt########
$location="eastus"
$SubscriptionIdval = "##########################"

$AppServicePlanName = "webappplan"########Plan Name 
$functionName= 'FPI'

# Executing that cmdlet opens a challenge/response window, enter your credentials 
Login-AzureRMAccount 


# Changing the Subscritption ID before executing the following Cmdlets
Set-AzureRmContext -SubscriptionId  $SubscriptionIdval # Changing the Subscritption ID before executing the following Cmdlets

# Creating a New resource-group
New-AzureRmResourceGroup -Name $resouregroupname -Location $location 

# Creating the App Service Plan (ASP)
New-AzureRmAppServicePlan -Name $AppServicePlanName -Location $location -ResourceGroupName $resouregroupname -Tier Free  

# Creating a New Webapp Sample-ASP service plan
New-AzureRmWebApp -Name $webappname -AppServicePlan $AppServicePlanName -ResourceGroupName $resouregroupname -Location $location 
Get-AzureRmWebApp -ResourceGroupName $resouregroupname -Name $webappname  



# Get publishing profile for the web app
$xml = [xml](Get-AzureRMWebAppPublishingProfile -Name $webappname `
-ResourceGroupName $resouregroupname `
-OutputFile null)


# Extract connection information from publishing profile
$username = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userName").value
$password = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@userPWD").value
$url = $xml.SelectNodes("//publishProfile[@publishMethod=`"FTP`"]/@publishUrl").value


# Upload files recursively 
Set-Location $appdirectory
$webclient = New-Object -TypeName System.Net.WebClient
$webclient.Credentials = New-Object System.Net.NetworkCredential($username,$password)
$files = Get-ChildItem -Path $appdirectory -Recurse | Where-Object{!($_.PSIsContainer)}

foreach ($file in $files)
{
    $relativepath = (Resolve-Path -Path $file.FullName -Relative).Replace(".\", "").Replace('\', '/')
    $uri = New-Object System.Uri("$url/$relativepath")
    "Uploading to " + $uri.AbsoluteUri
    $webclient.UploadFile($uri, $file.FullName)
} 
$webclient.Dispose()

#Skip if Error gets - It will not effect the script

#########################################################################################################

#Creating a Azure function APP

########################################################################################################
#Register resource providers

@('Microsoft.Web', 'Microsoft.Storage') | ForEach-Object {
    Register-AzureRmResourceProvider -ProviderNamespace $_
}

#Creating a storage account
$rnd = (New-Guid).ToString().Split('-')[0]
$storageAccountName = "awdocsstorefiedev3"
$storageSku = 'Standard_LRS'
$newStorageParams = @{
    ResourceGroupName = $resouregroupname
    AccountName       = $storageAccountName
    Location          = $location
    SkuName           = $storageSku
}
$storageAccount = New-AzureRmStorageAccount @newStorageParams
$storageAccount

#Get storage account connection string
$accountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $resouregroupname -AccountName $storageAccountName |
    Where-Object {$_.KeyName -eq 'Key1'} | Select-Object -ExpandProperty Value
$storageConnectionString = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=$accountKey"

#Creating function app

$functionAppName = 'awdocsfunc1' ########Need to a new Name 
$newFunctionAppParams = @{
    ResourceType      = 'Microsoft.Web/Sites'
    ResourceName      = $functionAppName
    Kind              = 'functionapp'
    Location          = $location
    ResourceGroupName = $resouregroupname
    Properties        = @{}
    Force             = $true
}
$functionApp = New-AzureRmResource @newFunctionAppParams
$functionApp


#Setting function app settings
$functionAppSettings = @{
    AzureWebJobDashboard                     = $storageConnectionString
    AzureWebJobsStorage                      = $storageConnectionString
    FUNCTIONS_EXTENSION_VERSION              = '~1'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING = $storageConnectionString
    WEBSITE_CONTENTSHARE                     = $storageAccountName
}
$setWebAppParams = @{
    Name = $functionAppName
    ResourceGroupName = $resouregroupname
    AppSettings = $functionAppSettings
}
$webApp = Set-AzureRmWebApp @setWebAppParams
$webApp


$functionContent = Get-Content ./FPI/run.ps1 -Raw
$functionSettings = Get-Content ./FPI/function.json | ConvertFrom-Json
$functionResourceId = '{0}/functions/{1}' -f $functionApp.ResourceId, $functionName
$functionProperties = @{
    config =@{
            bindings = $functionSettings.bindings
            }
            files = @{
                    'run.ps1' = "$functionContent"
                    }
            }

 $newFunctionParams= @{
    ResourceId = $functionResourceId
    Properties= $functionProperties
    ApiVersion = '2015-08-01'
    Force = $true
    }
    
$function = New-AzureRmResource @newFunctionParams
$function

#Deploy the function

$getSecretsParams = @{
    ResourceId = $function.ResourceId
    Action     = 'listsecrets'
    ApiVersion = '2015-08-01'
    Force      = $true
}
$functionSecrets = Invoke-AzureRmResourceAction @getSecretsParams
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
 
##################################################################################### 

# Test function

#####################################################################################
# GET
Invoke-RestMethod  -Uri "$($functionSecrets.trigger_url)&name=Brandon"
 
# POST
$body = @{
    name = 'Brandon'
} | ConvertTo-Json
Invoke-RestMethod -Uri $functionSecrets.trigger_url -Body $body -Method Post
