##########################################################################################
# <copyright file="Functions.ps1" company="Microsoft">
#     Copyright (c) Microsoft Corporation.  All rights reserved.
# </copyright>
# <summary>Functions.ps1 script.</summary>
##########################################################################################

#
# Global Functions
#

##########################################################################################
# <summary>
# Creates a new default Operations Manager connection based on the current registry settings.
# </summary>
# <param name="managementServerName">The name of the management server to connect to.</param>
# <param name="persistConnection">A flag indicating that the connection should be persisted.</param>
# <param name="interactive">A flag indicating that output is intended for an interactive user.</param>
##########################################################################################
function New-DefaultManagementGroupConnection([String] $managementServerName, [Boolean] $persistConnection, [System.Boolean] $interactive = $true)
{
    $MachineRegErrorMsg = "Can not find Operations Manager Management Server name for the local machine.";
    $UserRegKeyPath = "HKCU:\software\Microsoft\Microsoft Operations Manager\3.0\User Settings";
    $MachineRegKeyPath = "HKLM:\software\Microsoft\Microsoft Operations Manager\3.0\Machine Settings";
    $UserRegValueName = "SDKServiceMachine";
    $MachineRegValueName = "DefaultSDKServiceMachine";
    $ConnectingMsg = "Connecting to Operations Manager Management Server '{0}'.";
    $ConnectErrorMsg = "Can not connect to Operations Manager Management Server '{0}'.";
    $AccessDeniedErrorMsg = "Access is denied to Operations Manager Management Server '{0}'.";
    $ConnectPromptMsg = "Enter the name of the Operations Manager Management Server to connect to.";
    $ConnectPrompt = "Management Server";
    $serviceNotRunningErrorMsg = "The Data Access service is either not running or not yet initialized. Check the event log for more information.";
    $HostNotFoundErrorMsg = "No such host is known";

    $regKey = $null;
    $regValue = $null;
    
    # Set the initial server value to the MS argument.
    # If the argument is empty the normal registry lookup sequence will kickin.
    # If the argument is not empty the user will be connected to the specified connection.
    $server = $managementServerName;
    $drive = $null;

    # Get the User Operations Manager Product Registry Key
    if ($server -eq $null -or $server.Length -eq 0)
    {
        $regValue = Get-ItemProperty -path:$UserRegKeyPath -name:$UserRegValueName -ErrorAction:SilentlyContinue;

        if ($regValue -ne $null)
        {
            $server = $regValue.SDKServiceMachine;
        }
    }
    
    if ($server -eq $null -or $server.Length -eq 0)
    {
        # Get the Machine Operations Manager Product Registry Key if the user setting could not be found.
        $regValue = Get-ItemProperty -path:$MachineRegKeyPath -name:$MachineRegValueName -ErrorAction:SilentlyContinue;
        
        if ($regValue -ne $null)
        {
            $server = $regValue.DefaultSDKServiceMachine;
        }
    }
    
    # If the default Operations Manager Management Server name can not be found in the registry then default to 'localhost'.
    if ($server -eq $null -or $server.Length -eq 0)
    {
        if ($interactive -eq $true)
        {
            Write-WarningMessage $MachineRegErrorMsg | Out-Null;
        }
        
        $server = "localhost";
    }
    

    
    # Create a connection and make it the current location.
    $connection = $null;
    
    while ($connection -eq $null)
    {
        if ($server -ne $null -and $server.Length -gt 0)
        {
            # Format the connecting message.
            if ($interactive -eq $true)
            {
                $msg = $ConnectingMsg -f $server;
                Write-Host $msg | Out-Null;
            }
            
            # Create the new connection.
            if ($interactive -eq $true)
            {
                $error.Clear();
                $connection = New-SCOMManagementGroupConnection -ComputerName: $server -PassThru -ErrorAction:SilentlyContinue;
                
                # If the connection failed due to insufficient access then prompt for credentials.                
                if ($error.Count -gt 0 -and $error[0].Exception -is [Microsoft.EnterpriseManagement.Common.UnauthorizedAccessMonitoringException])
                {
                    $error.Clear();
                    $creds = Get-Credential;
                    $connection = New-SCOMManagementGroupConnection -ComputerName: $server -Credential: $creds  -PassThru -ErrorAction:SilentlyContinue;
                    if ($error.Count -gt 0 -and $error[0].Exception -is [Microsoft.EnterpriseManagement.Common.UnauthorizedAccessMonitoringException])
                    {
                        $errMsg = $AccessDeniedErrorMsg -f $server;
                        Write-WarningMessage $errMsg | Out-Null;
                    }                                                                
                }
                elseif ($error.Count -gt 0 -and $error[0].Exception -is [System.Net.Sockets.SocketException])
                {                                      
                   Write-WarningMessage $HostNotFoundErrorMsg | Out-Null;                   
                   $error.Clear();
                }                                
                elseif ($error.Count -gt 0 -and $error[0].Exception -is [Microsoft.EnterpriseManagement.Common.ServiceNotRunningException])
                {                   
                   Write-WarningMessage $serviceNotRunningErrorMsg  | Out-Null;                   
                   $error.Clear();
                }                                
                if ($connection -eq $null)
                {
                    $errMsg = $ConnectErrorMsg -f $server;
                    Write-WarningMessage $errMsg | Out-Null;
                }                
            }
            else
            {
                $connection = New-SCOMManagementGroupConnection -ComputerName: $server -PassThru -ErrorAction:Stop
            }
        }
        
        if ($connection -eq $null)
        {
            Write-Host $ConnectPromptMsg | Out-Null;
            $server = read-Host $ConnectPrompt;
        }
        else
        {
           
            
            # Update the registry with the current Operations Manager Management Server name.
            if ($persistConnection -eq $true)
            {
                $newRegKey = $null;
                $newRegKey = Get-Item -path:$UserRegKeyPath -errorAction:SilentlyContinue;
                
                if ($newRegKey -eq $null)
                {
                    $newRegKey = New-Item -path:$UserRegKeyPath -errorAction:SilentlyContinue;
                    
                    # The '-force' parameter is required when the parent key does not exist.
                    if ($newRegKey -eq $null)
                    {
                        $newRegKey = New-Item -path:$UserRegKeyPath -force -errorAction:SilentlyContinue;
                    }
                }
                
                if ($newRegKey -ne $null)
                {
                    $newRegValue = $null;
                    $newRegValue = Get-ItemProperty -path:$UserRegKeyPath -name:$UserRegValueName -errorAction:SilentlyContinue;
                    
                    if ($newRegValue -eq $null)
                    {
                        $newRegValue = New-ItemProperty -path:$UserRegKeyPath -name: $UserRegValueName -value:$server -errorAction:SilentlyContinue;
                    }
                    else
                    {
                        Set-ItemProperty -path:$UserRegKeyPath -name:$UserRegValueName -value:$server -errorAction:SilentlyContinue | Out-Null;
                    }
                }
            }
            break;
        }
    }
}

##########################################################################################
# <summary>
# Displays error information in red text for the specified error index.
# </summary>
# <param name="errorIndex">The error index for which to display error information..</param>
##########################################################################################
function Get-ErrorInfo([int]$errorIndex = 0)
{
    # Get the current foreground color and change the foreground color to red.
    $currentForegroundColor = $host.ui.rawui.foregroundcolor;

    $host.ui.rawui.foregroundcolor = "red";


    if ($error[$errorIndex].Exception -eq $null)
    {
        $error[$errorIndex];
    }
    else
    {
        $error[$errorIndex].Exception.ToString();

        $error[$errorIndex].Exception.GetType().Name;
    }

    # Restore the foreground color.
    $host.ui.rawui.foregroundcolor = $currentForegroundColor;
}

##########################################################################################
# <summary>
# Writes a string to the buffer with the specified number of indent spaces and
# adjusts the buffer width so that the string is not wrapped.
# </summary>
# <param name="indent">The number of spaces to indent the string.</param>
# <param name="string">The string to send to write out.</param>
##########################################################################################
function Out-StringNoWrap([int] $indent = 4, [string] $string)
{
    $width = $string.Length;
    $totalMinWidth = $indent + $width;
    $bs = $host.ui.rawui.BufferSize
    if ($bs -and ($totalMinWidth -ge $bs.Width))
    {
        $bs.Width = $totalMinWidth + 1;
        $host.ui.rawui.BufferSize = $bs;
    }

    $space = " ";
    $space *= $indent;

    $space + $string;
}


##########################################################################################
# <summary>
# Displays the Operations Manager Command Shell banner.
# </summary>
##########################################################################################
function Write-OperationsManagerClientShellBanner
{
    Out-StringNoWrap -string: ""
    Out-StringNoWrap -string: "Welcome to the System Center Operations Manager 2012 Command Shell.  This command shell is"
    Out-StringNoWrap -string: "designed to provide interactive and script based access to Operations Manager"
    Out-StringNoWrap -string: "data and operations.  This functionality is provided by a set of Operations"
    Out-StringNoWrap -string: "Manager commands."
    Out-StringNoWrap -string: ""
    Out-StringNoWrap -string: "To list all commands, type: Get-Command"
    Out-StringNoWrap -string: "To list all Operations Manager commands, type: get-command –module OperationsManager"
    Out-StringNoWrap -string: "To get help for a command, type: Get-Help [command name]"
    Out-StringNoWrap -string: ""
}

##########################################################################################
# <summary>
# Displays the specified message in yellow text.
# </summary>
# <param name="warning">The message to display.</param>
##########################################################################################
function Write-WarningMessage
{
    param([string]$warning)

    # Get the current foreground color and changes the foreground color to yellow
    $currentForegroundColor = $host.ui.rawui.foregroundcolor;
    $host.ui.rawui.foregroundcolor = "yellow";

    Write-Host $warning;

    # Restore the foreground color.
    $host.ui.rawui.foregroundcolor = $currentForegroundColor;
}



##########################################################################################
# <summary>
# Starts/Initializes the Operations Manager PowerShell Client snapin.
# </summary>
# <param name="managementServerName">The name of the management server to connect to.</param>
# <param name="persistConnection">A flag indicating that the connection should be persisted.</param>
# <param name="interactive">A flag indicating that output is intended for an interactive user.</param>
##########################################################################################
function Start-OperationsManagerClientShell([String] $managementServerName, [Boolean] $persistConnection, [Boolean] $interactive)
{

    if ($interactive -eq $true)
    {
        Write-OperationsManagerClientShellBanner;
        
        New-DefaultManagementGroupConnection -ManagementServerName: $managementServerName -PersistConnection: $persistConnection -Interactive: $true;
    }
    else
    {
        New-DefaultManagementGroupConnection -ManagementServerName: $managementServerName -PersistConnection: $persistConnection -Interactive: $false;
    }
}





# SIG # Begin signature block
# MIIa5AYJKoZIhvcNAQcCoIIa1TCCGtECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUGGAKjkD2SuSwPQ4mc0xEiL5P
# +CmgghWCMIIEwzCCA6ugAwIBAgITMwAAADPlJ4ajDkoqgAAAAAAAMzANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTMwMzI3MjAwODIz
# WhcNMTQwNjI3MjAwODIzWjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkY1MjgtMzc3Ny04QTc2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyt7KGQ8fllaC
# X9hCMtQIbbadwMLtfDirWDOta4FQuIghCl2vly2QWsfDLrJM1GN0WP3fxYlU0AvM
# /ZyEEXmsoyEibTPgrt4lQEWSTg1jCCuLN91PB2rcKs8QWo9XXZ09+hdjAsZwPrsi
# 7Vux9zK65HG8ef/4y+lXP3R75vJ9fFdYL6zSDqjZiNlAHzoiQeIJJgKgzOUlzoxn
# g99G+IVNw9pmHsdzfju0dhempaCgdFWo5WAYQWI4x2VGqwQWZlbq+abLQs9dVGQv
# gfjPOAAPEGvhgy6NPkjsSVZK7Jpp9MsPEPsHNEpibAGNbscghMpc0WOZHo5d7A+l
# Fkiqa94hLwIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFABYGz7txfEGk74xPTa0rAtd
# MvCBMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAAL/44wD6u9+OLm5fJ87UoOk+iM41AO4alm16uBviAP0b1Fq
# lTp1hegc3AfFTp0bqM4kRxQkTzV3sZy8J3uPXU/8BouXl/kpm/dAHVKBjnZIA37y
# mxe3rtlbIpFjOzJfNfvGkTzM7w6ZgD4GkTgTegxMvjPbv+2tQcZ8GyR8E9wK/EuK
# IAUdCYmROQdOIU7ebHxwu6vxII74mHhg3IuUz2W+lpAPoJyE7Vy1fEGgYS29Q2dl
# GiqC1KeKWfcy46PnxY2yIruSKNiwjFOPaEdHodgBsPFhFcQXoS3jOmxPb6897t4p
# sETLw5JnugDOD44R79ECgjFJlJidUUh4rR3WQLYwggTsMIID1KADAgECAhMzAAAA
# sBGvCovQO5/dAAEAAACwMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTEzMDEyNDIyMzMzOVoXDTE0MDQyNDIyMzMzOVowgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAOivXKIgDfgofLwFe3+t7ut2rChTPzrbQH2zjjPmVz+l
# URU0VKXPtIupP6g34S1Q7TUWTu9NetsTdoiwLPBZXKnr4dcpdeQbhSeb8/gtnkE2
# KwtA+747urlcdZMWUkvKM8U3sPPrfqj1QRVcCGUdITfwLLoiCxCxEJ13IoWEfE+5
# G5Cw9aP+i/QMmk6g9ckKIeKq4wE2R/0vgmqBA/WpNdyUV537S9QOgts4jxL+49Z6
# dIhk4WLEJS4qrp0YHw4etsKvJLQOULzeHJNcSaZ5tbbbzvlweygBhLgqKc+/qQUF
# 4eAPcU39rVwjgynrx8VKyOgnhNN+xkMLlQAFsU9lccUCAwEAAaOCAWAwggFcMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBRZcaZaM03amAeA/4Qevof5cjJB
# 8jBRBgNVHREESjBIpEYwRDENMAsGA1UECxMETU9QUjEzMDEGA1UEBRMqMzE1OTUr
# NGZhZjBiNzEtYWQzNy00YWEzLWE2NzEtNzZiYzA1MjM0NGFkMB8GA1UdIwQYMBaA
# FMsR6MrStBZYAck3LjMWFrlMmgofMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY0NvZFNpZ1BDQV8w
# OC0zMS0yMDEwLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljQ29kU2lnUENBXzA4LTMx
# LTIwMTAuY3J0MA0GCSqGSIb3DQEBBQUAA4IBAQAx124qElczgdWdxuv5OtRETQie
# 7l7falu3ec8CnLx2aJ6QoZwLw3+ijPFNupU5+w3g4Zv0XSQPG42IFTp8263Os8ls
# ujksRX0kEVQmMA0N/0fqAwfl5GZdLHudHakQ+hywdPJPaWueqSSE2u2WoN9zpO9q
# GqxLYp7xfMAUf0jNTbJE+fA8k21C2Oh85hegm2hoCSj5ApfvEQO6Z1Ktwemzc6bS
# Y81K4j7k8079/6HguwITO10g3lU/o66QQDE4dSheBKlGbeb1enlAvR/N6EXVruJd
# PvV1x+ZmY2DM1ZqEh40kMPfvNNBjHbFCZ0oOS786Du+2lTqnOOQlkgimiGaCMIIF
# vDCCA6SgAwIBAgIKYTMmGgAAAAAAMTANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZIm
# iZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQD
# EyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwODMx
# MjIxOTMyWhcNMjAwODMxMjIyOTMyWjB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJyWVwZMGS/HZpgICBC
# mXZTbD4b1m/My/Hqa/6XFhDg3zp0gxq3L6Ay7P/ewkJOI9VyANs1VwqJyq4gSfTw
# aKxNS42lvXlLcZtHB9r9Jd+ddYjPqnNEf9eB2/O98jakyVxF3K+tPeAoaJcap6Vy
# c1bxF5Tk/TWUcqDWdl8ed0WDhTgW0HNbBbpnUo2lsmkv2hkL/pJ0KeJ2L1TdFDBZ
# +NKNYv3LyV9GMVC5JxPkQDDPcikQKCLHN049oDI9kM2hOAaFXE5WgigqBTK3S9dP
# Y+fSLWLxRT3nrAgA9kahntFbjCZT6HqqSvJGzzc8OJ60d1ylF56NyxGPVjzBrAlf
# A9MCAwEAAaOCAV4wggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMsR6MrS
# tBZYAck3LjMWFrlMmgofMAsGA1UdDwQEAwIBhjASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBT90TFO0yaKleGYYDuoMW+mPLzYLTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTAfBgNVHSMEGDAWgBQOrIJgQFYnl+UlE/wq4QpTlVnk
# pDBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEE
# SDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDANBgkqhkiG9w0BAQUFAAOCAgEAWTk+
# fyZGr+tvQLEytWrrDi9uqEn361917Uw7LddDrQv+y+ktMaMjzHxQmIAhXaw9L0y6
# oqhWnONwu7i0+Hm1SXL3PupBf8rhDBdpy6WcIC36C1DEVs0t40rSvHDnqA2iA6VW
# 4LiKS1fylUKc8fPv7uOGHzQ8uFaa8FMjhSqkghyT4pQHHfLiTviMocroE6WRTsgb
# 0o9ylSpxbZsa+BzwU9ZnzCL/XB3Nooy9J7J5Y1ZEolHN+emjWFbdmwJFRC9f9Nqu
# 1IIybvyklRPk62nnqaIsvsgrEA5ljpnb9aL6EiYJZTiU8XofSrvR4Vbo0HiWGFzJ
# NRZf3ZMdSY4tvq00RBzuEBUaAF3dNVshzpjHCe6FDoxPbQ4TTj18KUicctHzbMrB
# 7HCjV5JXfZSNoBtIA1r3z6NnCnSlNu0tLxfI5nI3EvRvsTxngvlSso0zFmUeDord
# EN5k9G/ORtTTF+l5xAS00/ss3x+KnqwK+xMnQK3k+eGpf0a7B2BHZWBATrBC7E7t
# s3Z52Ao0CW0cgDEf4g5U3eWh++VHEK1kmP9QFi58vwUheuKVQSdpw5OPlcmN2Jsh
# rg1cnPCiroZogwxqLbt2awAdlq3yFnv2FoMkuYjPaqhHMS+a3ONxPdcAfmJH0c6I
# ybgY+g5yjcGjPa8CQGr/aZuW4hCoELQ3UAjWwz0wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TGCBMwwggTI
# AgEBMIGQMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAh
# BgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBAhMzAAAAsBGvCovQO5/d
# AAEAAACwMAkGBSsOAwIaBQCggeUwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFOZl
# 5WoHvVTjbugMnAorCmlgafD0MIGEBgorBgEEAYI3AgEMMXYwdKBWgFQAUwB5AHMA
# dABlAG0AIABDAGUAbgB0AGUAcgAgADIAMAAxADIAIABSADIAIAAtACAATwBwAGUA
# cgBhAHQAaQBvAG4AcwAgAE0AYQBuAGEAZwBlAHKhGoAYaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAMIBv5XLs0zkHuFYaWwhejvfYzep
# 4BVYa/1lao7q9BbjCy7xLzeIBIgLaQ9EJGbP5V3QtsIo0HTNxH3/v4CcqudD8lc+
# majFssWbdM4w5WlWlOeOYVHu1qkaQscj2K57JsbjhoPMo2ztf3hfXJYJZgp38Bzn
# oqz3Sg5l3Pzh30a8rXnHkFmynGagNOBWgKdnOdW3v/vt7bMSamyfs/tMnP4QRmCn
# NMvTkthBfliudlkPkbR8ffEbO2xt8nPE0/zwEUJa6sKxui3o2BEPdXj+ihomxGBY
# ZgbkNYeu95xq9VKTbL9x5P0BRxunnUQMF6eWc2R73zBP25ZNskDP5DqyIymhggIo
# MIICJAYJKoZIhvcNAQkGMYICFTCCAhECAQEwgY4wdzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEhMB8GA1UEAxMYTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBAhMzAAAAM+UnhqMOSiqAAAAAAAAzMAkGBSsOAwIaBQCgXTAYBgkqhkiG
# 9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0xMzA5MDYyMzE5MDJa
# MCMGCSqGSIb3DQEJBDEWBBQSTXvEuuhH7GtY2wXClBXws7QlpTANBgkqhkiG9w0B
# AQUFAASCAQAK4dDDQedAOBGeyYYNYhjHATIz0iClRbLbDDQr9D/VWFzeOTCWb+uZ
# 5iy+3yfFWee08kFQ9w5+Iw9BzqiOfvS2b0CPv1IILuJPcHHTDK1nysCYxqaS6yTm
# 2MDoop9+2hjBru6nT+nqP+HYVhNxAT8X3BZIdp7Hb/xFVtgEQWVZ2VeiMnabf9je
# oUdPGvXcTZWEoaW+5BOTJIEzGaMzJHePEsPPPXYAbq5M/O6t8IhE3SkoS5ZMIeNV
# PbSTil0wUoi/FtrJV4kXREaHqjEehpVhIShuSKeB1We3N1HO1SLzpYIQDT4Lq/mY
# h3jbGnAohGi22mlMGPlt0aECV86335wG
# SIG # End signature block
