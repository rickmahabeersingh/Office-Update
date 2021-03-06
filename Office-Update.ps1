﻿<#PSScriptInfo

.VERSION 20.03.20

.GUID 72cb5483-744e-4a7d-bcad-e04462ea2c2e

.AUTHOR Mike Galvin Contact: mike@gal.vin / twitter.com/mikegalvin_

.COMPANYNAME Mike Galvin

.COPYRIGHT (C) Mike Galvin. All rights reserved.

.TAGS Office 2019 365 Click-to-run C2R updates

.LICENSEURI

.PROJECTURI https://gal.vin/2019/06/16/automated-office-updates

.ICONURI

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

#>

<#
    .SYNOPSIS
    Office Update Utility - Office Update Manager.

    .DESCRIPTION
    Checks for updates of Office 365/2019.

    To send a log file via e-mail using ssl and an SMTP password you must generate an encrypted password file.
    The password file is unique to both the user and machine.

    To create the password file run this command as the user and on the machine that will use the file:

    $creds = Get-Credential
    $creds.Password | ConvertFrom-SecureString | Set-Content c:\foo\ps-script-pwd.txt

    .PARAMETER Office
    The folder containing the Office Deployment Tool (ODT).

    .PARAMETER Config
    The name of the configuration xml file for the Office Deployment Tool.
    It must be located in the same folder as the Office deployment tool.

    .PARAMETER Days
    The number of days that you wish to keep old update files for.
    If you do not configure this option, no old update files will be removed.

    .PARAMETER NoBanner
    Use this option to hide the ASCII art title in the console.

    .PARAMETER L
    The path to output the log file to.
    The file name will be Office-Update_YYYY-MM-dd_HH-mm-ss.log
    Do not add a trailing \ backslash.

    .PARAMETER Subject
    The subject line for the e-mail log.
    Encapsulate with single or double quotes.
    If no subject is specified, the default of "Office Update Utility Log" will be used.

    .PARAMETER SendTo
    The e-mail address the log should be sent to.

    .PARAMETER From
    The e-mail address the log should be sent from.

    .PARAMETER Smtp
    The DNS name or IP address of the SMTP server.

    .PARAMETER User
    The user account to authenticate to the SMTP server.

    .PARAMETER Pwd
    The txt file containing the encrypted password for SMTP authentication.

    .PARAMETER UseSsl
    Configures the utility to connect to the SMTP server using SSL.

    .EXAMPLE
    Office-Update.ps1 -Office \\Apps01\Software\Office365 -Config config-365-x64.xml -Days 30 -L C:\scripts\logs
    -Subject 'Server: Office Update' -SendTo me@contoso.com -From OffUpdate@contoso.com -Smtp exch01.contoso.com
    -User me@contoso.com -Pwd P@ssw0rd -UseSsl

    The above command will download any Office updates for the version and channel configured in config-365-x64.xml
    to the Office files directory \\Apps01\Software\Office365. Any update files older than 30 days will be removed.
    If the download is successful the log file will be output to C:\scripts\logs and e-mailed with a custom subject line.
#>

## Set up command line switches.
[CmdletBinding()]
Param(
    [parameter(Mandatory=$True)]
    [alias("Office")]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    $OfficeSrc,
    [parameter(Mandatory=$True)]
    [alias("Config")]
    $Cfg,
    [alias("Days")]
    $Time,
    [alias("L")]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    $LogPath,
    [alias("Subject")]
    $MailSubject,
    [alias("SendTo")]
    $MailTo,
    [alias("From")]
    $MailFrom,
    [alias("Smtp")]
    $SmtpServer,
    [alias("User")]
    $SmtpUser,
    [alias("Pwd")]
    [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
    $SmtpPwd,
    [switch]$UseSsl,
    [switch]$NoBanner)

If ($NoBanner -eq $False)
{
    Write-Host -Object ""
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "                                                                "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "     ___  __  __ _                            _       _         "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "    /___\/ _|/ _(_) ___ ___   /\ /\ _ __   __| | __ _| |_ ___   "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "   //  // |_| |_| |/ __/ _ \ / / \ \ '_ \ / _  |/ _  | __/ _ \  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "  / \_//|  _|  _| | (_|  __/ \ \_/ / |_) | (_| | (_| | ||  __/  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "  \___/ |_| |_| |_|\___\___|  \___/| .__/ \__,_|\__,_|\__\___|  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "                                   |_|                          "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "         _   _ _ _ _                                            "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "   /\ /\| |_(_) (_) |_ _   _                                    "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "  / / \ \ __| | | | __| | | |           3 6 5                   "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "  \ \_/ / |_| | | | |_| |_| |          2 0 1 9                  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "   \___/ \__|_|_|_|\__|\__, |        Click-to-Run               "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "                       |___/                                    "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "                                                                "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "    Mike Galvin    https://gal.vin    Version 20.03.20  +       "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black -Object "                                                                "
    Write-Host -Object ""
}

## If logging is configured, start logging.
## If the log file already exists, clear it.
If ($LogPath)
{
    $LogFile = ("Office-Update_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    $Log = "$LogPath\$LogFile"

    $LogT = Test-Path -Path $Log

    If ($LogT)
    {
        Clear-Content -Path $Log
    }

    Add-Content -Path $Log -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log started"
}

## Function to get date in specific format.
Function Get-DateFormat
{
    Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

## Function for logging.
Function Write-Log($Type, $Event)
{
    If ($Type -eq "Info")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$(Get-DateFormat) [INFO] $Event"
        }
        
        Write-Host -Object "$(Get-DateFormat) [INFO] $Event"
    }

    If ($Type -eq "Succ")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$(Get-DateFormat) [SUCCESS] $Event"
        }

        Write-Host -ForegroundColor Green -Object "$(Get-DateFormat) [SUCCESS] $Event"
    }

    If ($Type -eq "Err")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$(Get-DateFormat) [ERROR] $Event"
        }

        Write-Host -ForegroundColor Red -BackgroundColor Black -Object "$(Get-DateFormat) [ERROR] $Event"
    }

    If ($Type -eq "Conf")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$Event"
        }

        Write-Host -ForegroundColor Cyan -Object "$Event"
    }
}

##
## Display the current config and log if configured.
##
Write-Log -Type Conf -Event "************ Running with the following config *************."
Write-Log -Type Conf -Event "Office folder:.........$OfficeSrc."
Write-Log -Type Conf -Event "Config file:...........$Cfg."
Write-Log -Type Conf -Event "Days to keep updates:..$Time days."

If ($Null -ne $LogPath)
{
    Write-Log -Type Conf -Event "Logs directory:........$LogPath."
}

else {
    Write-Log -Type Conf -Event "Logs directory:........No Config"
}

If ($MailTo)
{
    Write-Log -Type Conf -Event "E-mail log to:.........$MailTo."
}

else {
    Write-Log -Type Conf -Event "E-mail log to:.........No Config"
}

If ($MailFrom)
{
    Write-Log -Type Conf -Event "E-mail log from:.......$MailFrom."
}

else {
    Write-Log -Type Conf -Event "E-mail log from:.......No Config"
}

If ($MailSubject)
{
    Write-Log -Type Conf -Event "E-mail subject:........$MailSubject."
}

else {
    Write-Log -Type Conf -Event "E-mail subject:........Default"
}

If ($SmtpServer)
{
    Write-Log -Type Conf -Event "SMTP server is:........$SmtpServer."
}

else {
    Write-Log -Type Conf -Event "SMTP server is:........No Config"
}

If ($SmtpUser)
{
    Write-Log -Type Conf -Event "SMTP user is:..........$SmtpUser."
}

else {
    Write-Log -Type Conf -Event "SMTP user is:..........No Config"
}

If ($SmtpPwd)
{
    Write-Log -Type Conf -Event "SMTP pwd file:.........$SmtpPwd."
}

else {
    Write-Log -Type Conf -Event "SMTP pwd file:.........No Config"
}

Write-Log -Type Conf -Event "-UseSSL switch is:.....$UseSsl."
Write-Log -Type Conf -Event "************************************************************"
Write-Log -Type Info -Event "Process started"
##
## Display current config ends here.
##

#Run update process.
& $OfficeSrc\setup.exe /download $OfficeSrc\$Cfg

## Location of the office source files.
$UpdateFolder = "$OfficeSrc\Office\Data"

## Check the last write time of the office source files folder if it is greater than the previous day.
$Updated = (Get-ChildItem -Path $UpdateFolder | Where-Object CreationTime -gt (Get-Date).AddDays(-1)).Count

## If the Updated variable returns as not 0 then continue.
If ($Updated -ne 0)
{
    #$VerName = Get-ChildItem -Path $UpdateFolder -Directory | Where-Object CreationTime –gt (Get-Date).AddDays(-1) | Select-Object -ExpandProperty Name
    $VerName = Get-ChildItem -Path $UpdateFolder -Directory | Sort-Object LastWriteTime | Select-Object -last 1 | Select-Object -ExpandProperty Name
    Write-Log -Type Info -Event "Office source files were updated."
    Write-Log -Type Info -Event "Latest version is: $VerName"

    If ($Null -ne $Time)
    {
        $FilesToDel = Get-ChildItem -Path $UpdateFolder | Where-Object LastWriteTime –lt (Get-Date).AddDays(-$Time)

        If ($FilesToDel.count -ne 0)
        {
            Write-Log -Type Info -Event "The following old Office files were removed:"
            Get-ChildItem -Path $UpdateFolder | Where-Object LastWriteTime –lt (Get-Date).AddDays(-$Time)
            Get-ChildItem -Path $UpdateFolder | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-$Time)} | Select-Object -Property Name, LastWriteTime | Format-Table -HideTableHeaders | Out-File -Append $Log -Encoding ASCII

            ## If configured, remove the old files.
            Get-ChildItem $UpdateFolder | Where-Object {$_.LastWriteTime –lt (Get-Date).AddDays(-$Time)} | Remove-Item -Recurse
        }
    }

    Write-Log -Type Info -Event "Process finished"

    ## If logging is configured then finish the log file.
    If ($LogPath)
    {
        Add-Content -Path $Log -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log finished"

        ## This whole block is for e-mail, if it is configured.
        If ($SmtpServer)
        {
            ## Default e-mail subject if none is configured.
            If ($Null -eq $MailSubject)
            {
                $MailSubject = "Office Update Utility Log"
            }

            ## Setting the contents of the log to be the e-mail body. 
            $MailBody = Get-Content -Path $Log | Out-String

            ## If an smtp password is configured, get the username and password together for authentication.
            ## If an smtp password is not provided then send the e-mail without authentication and obviously no SSL.
            If ($SmtpPwd)
            {
                $SmtpPwdEncrypt = Get-Content $SmtpPwd | ConvertTo-SecureString
                $SmtpCreds = New-Object System.Management.Automation.PSCredential -ArgumentList ($SmtpUser, $SmtpPwdEncrypt)

                ## If -ssl switch is used, send the email with SSL.
                ## If it isn't then don't use SSL, but still authenticate with the credentials.
                If ($UseSsl)
                {
                    Send-MailMessage -To $MailTo -From $MailFrom -Subject $MailSubject -Body $MailBody -SmtpServer $SmtpServer -UseSsl -Credential $SmtpCreds
                }

                else {
                    Send-MailMessage -To $MailTo -From $MailFrom -Subject $MailSubject -Body $MailBody -SmtpServer $SmtpServer -Credential $SmtpCreds
                }
            }

            else {
                Send-MailMessage -To $MailTo -From $MailFrom -Subject $MailSubject -Body $MailBody -SmtpServer $SmtpServer
            }
        }
    }
}

Write-Log -Type Info -Event "No updates."
Write-Log -Type Info -Event "Process finished"

## End