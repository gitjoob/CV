<#
.SYNOPSIS
    Automated Employee Offboarding Integration Script
    
.DESCRIPTION
    This script automates the offboarding process for employees managed in Hailey HR system.
    It performs the following operations:
    
    📋 Main Functions:
    1. 🔗 Connects to Microsoft Graph API (using Managed Identity in Azure or interactive auth locally)
    2. 📞 Fetches leaving employees from Hailey HR API
    3. 📅 Updates EmployeeLeaveDateTime in Microsoft Entra ID user accounts
    4. 🧹 Clears custom attributes (extensionAttribute1) on the employee's last day
    5. 📊 Generates DLP (Data Loss Prevention) configuration CSV for Microsoft Purview
    6. ☁️ Uploads DLP configuration to Azure Storage
    7. 📤 Pushes HR connector data to Microsoft 365 Compliance Center
    
    🔐 Required Permissions:
    - Microsoft Graph: User.Read.All, User-LifeCycleInfo.ReadWrite.All
    - Azure: Storage Account access via Managed Identity
    - Hailey API: Valid API token stored in Azure Automation
    
    🤖 Designed to run in:
    - Azure Automation (using Managed Identity)
    - Local environment (interactive authentication)
    
.NOTES
    Created by: Johan Öberg
    Last Updated: January 2026
    Version: 2.0
#>
