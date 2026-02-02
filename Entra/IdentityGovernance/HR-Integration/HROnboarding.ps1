# Created by Johan Öberg

<#
.SYNOPSIS
    Automates employee onboarding by syncing data from Hailey HR API with Microsoft 365 and Exchange Online.

.DESCRIPTION
    This PowerShell script integrates with the Hailey HR system to automate employee onboarding tasks.
    It includes functions for:
    - Connecting to Microsoft Graph and Exchange Online (supports both Azure Automation and local execution)
    - Fetching employee data from Hailey HR API
    - Setting team assignments in Exchange Online based on Hailey team IDs
    - Managing company name attributes for users
    - Handling employee visibility in address lists based on joining dates
    - Processing both "WillJoin" and "InService" employees
    
    The script uses managed identity when running in Azure Automation and interactive authentication
    when running locally. Team assignments are mapped from Hailey team IDs to Exchange CustomAttribute1.
    Company name is set within a 14-day window before the employee's joining date.

.NOTES
    File Name      : run-HaileyOnboarding.ps1
    Author         : Johan Öberg
    Prerequisite   : Microsoft.Graph, ExchangeOnlineManagement modules
    Version        : 1.0
    
.EXAMPLE
    .\run-HaileyOnboarding.ps1
    Runs the script to process employee onboarding from Hailey HR system.
#>