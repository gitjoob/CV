<#
.SYNOPSIS
    Enrollment Phase script for Phishing Resistant MFA implementation.

.DESCRIPTION
    This script sets up the enrollment phase for Phishing Resistant MFA by:
    1. Creating three Entra ID groups for platform-specific enforcement (Windows, iOS, macOS)
    2. Creating three Conditional Access policies with Phishing Resistant MFA authentication strength
    3. Setting policies to report-only mode (enabledForReportingButNotEnforced)

.NOTES
    Requires:
    - Microsoft.Graph.Groups module
    - Microsoft.Graph.Identity.SignIns module
    - Appropriate permissions: Group.ReadWrite.All, Policy.ReadWrite.ConditionalAccess
#>

#Requires -Modules Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns

# Check for required modules
Write-Host "Checking required PowerShell modules..." -ForegroundColor Cyan

$requiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.Groups",
    "Microsoft.Graph.Identity.SignIns",
    "Microsoft.Graph.Identity.Governance",
    "Microsoft.Graph.Users"
)

foreach ($module in $requiredModules) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-Host "✓ Module '$module' is installed" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Module '$module' is NOT installed" -ForegroundColor Red
        Write-Host "  Install it using: Install-Module -Name $module -Scope CurrentUser" -ForegroundColor Yellow
        exit
    }
}

# Connect to Microsoft Graph with required scopes
Write-Host "`nConnecting to Microsoft Graph..." -ForegroundColor Cyan

try {
    Connect-MgGraph -Scopes "Group.ReadWrite.All", "Policy.ReadWrite.ConditionalAccess", "Policy.Read.All", "User.Read.All", "RoleManagement.Read.Directory" -ErrorAction Stop
    Write-Host "✓ Successfully connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to connect to Microsoft Graph. Error: $_" -ForegroundColor Red
    exit
}

# Verify granted permissions
Write-Host "`nVerifying granted permissions..." -ForegroundColor Cyan

$context = Get-MgContext
$requiredScopes = @("Group.ReadWrite.All", "Policy.ReadWrite.ConditionalAccess", "Policy.Read.All", "User.Read.All", "RoleManagement.Read.Directory")

foreach ($scope in $requiredScopes) {
    if ($context.Scopes -contains $scope) {
        Write-Host "✓ Scope '$scope' is granted" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Scope '$scope' is NOT granted" -ForegroundColor Yellow
        Write-Host "  You may need to consent to additional permissions" -ForegroundColor Yellow
    }
}

# Check for required Entra ID roles
Write-Host "`nChecking required Entra ID roles..." -ForegroundColor Cyan

try {
    $currentUser = Get-MgUser -UserId $context.Account -ErrorAction Stop
}
catch {
    Write-Host "✗ Failed to get current user information. Error: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit
}

$requiredRoles = @(
    "Conditional Access Administrator",
    "Groups Administrator",
    "Security Administrator"
)

try {
    $activeRoles = Get-MgUserMemberOf -UserId $currentUser.Id -All -ErrorAction Stop | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.directoryRole' }
    $activeRoleNames = $activeRoles | ForEach-Object { $_.AdditionalProperties.displayName }
}
catch {
    Write-Host "✗ Failed to get user's active roles. Error: $_" -ForegroundColor Red
    $activeRoleNames = @()
}

# Check for eligible roles and PIM-enabled groups (requires privileged access)
$eligibleRoleNames = @()
$pimGroups = @()

try {
    $eligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$($currentUser.Id)'" -All -ErrorAction Stop
    $eligibleRoleNames = $eligibleAssignments | ForEach-Object {
        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId -ErrorAction Stop
        $roleDefinition.DisplayName
    }
}
catch {
    Write-Host "  Unable to check PIM eligible roles (may require additional permissions)" -ForegroundColor Gray
}

try {
    $pimGroups = Get-MgUserMemberOf -UserId $currentUser.Id -All -ErrorAction Stop | Where-Object {
        $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' -and
        $_.AdditionalProperties.isAssignableToRole -eq $true
    }
}
catch {
    Write-Host "  Unable to check PIM-enabled groups" -ForegroundColor Gray
}

$allRoles = ($activeRoleNames + $eligibleRoleNames) | Select-Object -Unique

# Check for overly-privileged roles FIRST
$privilegedRoles = @(
    "Global Administrator",
    "Privileged Role Administrator"
)

$hasPrivilegedRole = $false
foreach ($privRole in $privilegedRoles) {
    if ($activeRoleNames -contains $privRole) {
        $hasPrivilegedRole = $true
        Write-Host "✓ Role '$privRole' is assigned (covers all required permissions)" -ForegroundColor Green
        Write-Host "  ⚠️  This role has more permissions than necessary." -ForegroundColor Yellow
        Write-Host "  Consider using a less privileged account following the principle of least privilege." -ForegroundColor Yellow
    }
}

# If user has privileged role, skip checking for individual roles
if ($hasPrivilegedRole) {
    if ($pimGroups.Count -gt 0) {
        Write-Host "`nPIM-enabled group memberships:" -ForegroundColor Cyan
        foreach ($group in $pimGroups) {
            Write-Host "  • $($group.AdditionalProperties.displayName)" -ForegroundColor Gray
        }
    }
}
else {
    # Check for required roles only if no privileged role is assigned
    $missingRoles = @()
    foreach ($role in $requiredRoles) {
        if ($allRoles -contains $role) {
            Write-Host "✓ Role '$role' is assigned" -ForegroundColor Green
        }
        else {
            Write-Host "✗ Role '$role' is NOT assigned" -ForegroundColor Red
            $missingRoles += $role
        }
    }

    if ($pimGroups.Count -gt 0) {
        Write-Host "`nPIM-enabled group memberships:" -ForegroundColor Cyan
        foreach ($group in $pimGroups) {
            Write-Host "  • $($group.AdditionalProperties.displayName)" -ForegroundColor Gray
        }
    }

    if ($missingRoles.Count -gt 0) {
        Write-Host "`n✗ Missing required roles. Please ensure you have one of the following:" -ForegroundColor Red
        foreach ($role in $missingRoles) {
            Write-Host "  - $role" -ForegroundColor Yellow
        }
        Write-Host "`nIf you have eligible roles, activate them in PIM before running this script." -ForegroundColor Yellow
        $continue = Read-Host "`nDo you want to continue anyway? (Y/N)"
        if ($continue -ne "Y" -and $continue -ne "y") {
            Disconnect-MgGraph
            exit
        }
    }
}

# Prerequisites Check
Write-Host "`nChecking prerequisites..." -ForegroundColor Cyan

# Check if Passwordless Phone Sign-in is enabled
try {
    $microsoftAuthenticatorPolicy = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId "MicrosoftAuthenticator"
    $phoneSignInEnabled = $microsoftAuthenticatorPolicy.State -eq "enabled"
    
    if ($phoneSignInEnabled) {
        Write-Host "✓ Passwordless Phone Sign-in (Microsoft Authenticator) is enabled" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Passwordless Phone Sign-in (Microsoft Authenticator) is NOT enabled" -ForegroundColor Yellow
        $findings += "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Microsoft Authenticator was found as disabled"
        $enableAuthenticator = Read-Host "Would you like to enable it now? (Y/N)"
        
        if ($enableAuthenticator -eq "Y" -or $enableAuthenticator -eq "y") {
            try {
                Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod" -NoWelcome
                $requiredScopes = @("Policy.ReadWrite.AuthenticationMethod")
                foreach ($scope in $requiredScopes) {
                    if ($context.Scopes -contains $scope) {
                        Write-Host "✓ Scope '$scope' is granted" -ForegroundColor Green
                    }
                    else {
                        Write-Host "✗ Scope '$scope' is NOT granted" -ForegroundColor Yellow
                        Write-Host "  You may need to consent to additional permissions" -ForegroundColor Yellow
                    }
                }

                Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId "MicrosoftAuthenticator" -State "enabled"
                Write-Host "✓ Microsoft Authenticator has been enabled" -ForegroundColor Green
            }
            catch {
                Write-Host "✗ Failed to enable Microsoft Authenticator. Error: $_" -ForegroundColor Red
                exit
            }
        }
        else {
            Write-Host "  Please enable it manually in Azure AD > Security > Authentication methods > Microsoft Authenticator" -ForegroundColor Yellow
            exit
        }
    }
}
catch {
    Write-Host "✗ Failed to check Microsoft Authenticator policy. Error: $_" -ForegroundColor Red
    exit
}

# Check if FIDO2 Security Key is enabled
try {
    $fido2Policy = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId "Fido2"
    $fido2Enabled = $fido2Policy.State -eq "enabled"
    
    if ($fido2Enabled) {
        Write-Host "✓ FIDO2 Security Key is enabled" -ForegroundColor Green
    }
    else {
        Write-Host "✗ FIDO2 Security Key is NOT enabled" -ForegroundColor Yellow
        $findings += "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - FIDO2 Security Key was found as disabled"
        $enableFido2 = Read-Host "Would you like to enable it now? (Y/N)"
        
        if ($enableFido2 -eq "Y" -or $enableFido2 -eq "y") {
            try {
                Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod" -NoWelcome
                $requiredScopes = @("Policy.ReadWrite.AuthenticationMethod")
                foreach ($scope in $requiredScopes) {
                    if ($context.Scopes -contains $scope) {
                        Write-Host "✓ Scope '$scope' is granted" -ForegroundColor Green
                    }
                    else {
                        Write-Host "✗ Scope '$scope' is NOT granted" -ForegroundColor Yellow
                        Write-Host "  You may need to consent to additional permissions" -ForegroundColor Yellow
                    }
                }

                Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId "Fido2" -State "enabled"
                Write-Host "✓ FIDO2 Security Key has been enabled" -ForegroundColor Green
            }
            catch {
                Write-Host "✗ Failed to enable FIDO2 Security Key. Error: $_" -ForegroundColor Red
                exit
            }
        }
        else {
            Write-Host "  Please enable it manually in Azure AD > Security > Authentication methods > FIDO2 Security Key" -ForegroundColor Yellow
            exit
        }
    }
}
catch {
    Write-Host "✗ Failed to check FIDO2 policy. Error: $_" -ForegroundColor Red
    exit
}

# Check for weak authentication methods (SMS, Voice, Email)
Write-Host "`nChecking for weak authentication methods..." -ForegroundColor Cyan
$findingsPath = Join-Path $PSScriptRoot "Findings.txt"
$findings = @()

$weakMethods = @(
    @{ Id = "Sms"; Name = "SMS" },
    @{ Id = "Voice"; Name = "Voice" },
    @{ Id = "Email"; Name = "Email OTP" }
)

foreach ($method in $weakMethods) {
    try {
        $methodPolicy = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId $method.Id -ErrorAction SilentlyContinue
        
        if ($methodPolicy -and $methodPolicy.State -eq "enabled") {
            Write-Host "⚠ $($method.Name) authentication is enabled (not recommended for phishing-resistant MFA)" -ForegroundColor Yellow
            $disableMethod = Read-Host "Would you like to disable $($method.Name) authentication? (Y/N)"
            
            if ($disableMethod -eq "Y" -or $disableMethod -eq "y") {
                Connect-MgGraph -Scopes "Policy.ReadWrite.AuthenticationMethod" -NoWelcome
                $requiredScopes = @("Policy.ReadWrite.AuthenticationMethod")
                foreach ($scope in $requiredScopes) {
                    if ($context.Scopes -contains $scope) {
                        Write-Host "✓ Scope '$scope' is granted" -ForegroundColor Green
                    }
                    else {
                        Write-Host "✗ Scope '$scope' is NOT granted" -ForegroundColor Yellow
                        Write-Host "  You may need to consent to additional permissions" -ForegroundColor Yellow
                    }
                }
                try {
                    Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId $method.Id -State "disabled"
                    Write-Host "✓ $($method.Name) authentication has been disabled" -ForegroundColor Green
                    $findings += "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($method.Name) authentication was enabled and has been disabled"
                }
                catch {
                    Write-Host "✗ Failed to disable $($method.Name) authentication. Error: $_" -ForegroundColor Red
                    $findings += "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($method.Name) authentication is enabled - FAILED TO DISABLE: $_"
                }
            }
            else {
                $findings += "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $($method.Name) authentication is enabled - USER DECLINED TO DISABLE"
            }
        }
    }
    catch {
        Write-Host "  Could not check $($method.Name) authentication method" -ForegroundColor Gray
    }
}

# Write findings to file if any exist
if ($findings.Count -gt 0) {
    try {
        $findings | Out-File -FilePath $findingsPath -Append -Encoding UTF8
        Write-Host "`n✓ Findings logged to $findingsPath" -ForegroundColor Cyan
    }
    catch {
        Write-Host "✗ Failed to write findings to file. Error: $_" -ForegroundColor Red
    }
}

Write-Host "✓ All prerequisites met`n" -ForegroundColor Green

# Step 1: Create Entra ID Groups
Write-Host "Creating Entra ID groups for MFA enrollment..." -ForegroundColor Cyan

$groups = @(
    @{ Name = "Windows Enforcement"; Description = "Users enrolled in Phishing Resistant MFA - Windows Platform" },
    @{ Name = "iOS Enforcement"; Description = "Users enrolled in Phishing Resistant MFA - iOS Platform" },
    @{ Name = "MacOS Enforcement"; Description = "Users enrolled in Phishing Resistant MFA - macOS Platform" }
)

$groupIds = @{}

foreach ($group in $groups) {
    try {
        # Check if group already exists
        $existingGroup = Get-MgGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
        
        if ($existingGroup) {
            Write-Host "⚠ Group already exists: $($group.Name) (ID: $($existingGroup.Id))" -ForegroundColor Yellow
            Write-Host "  Using existing group..." -ForegroundColor Gray
            $groupIds[$group.Name] = $existingGroup.Id
        }
        else {
            $newGroup = New-MgGroup -DisplayName $group.Name -Description $group.Description -MailEnabled:$false -SecurityEnabled:$true -MailNickname ($group.Name -replace '\s', '')
            $groupIds[$group.Name] = $newGroup.Id
            Write-Host "✓ Created group: $($group.Name) (ID: $($newGroup.Id))" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "✗ Failed to create group: $($group.Name). Error: $_" -ForegroundColor Red
    }
}

# Log Group IDs to file
Write-Host "`nLogging Group IDs to file..." -ForegroundColor Cyan
$groupsFilePath = Join-Path $PSScriptRoot "Groups.csv"
try {
    $groupOutput = @()
    foreach ($groupName in $groupIds.Keys) {
        $groupOutput += [PSCustomObject]@{
            GroupName = $groupName
            GroupId = $groupIds[$groupName]
            CreatedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }
    }
    $groupOutput | Export-Csv -Path $groupsFilePath -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Group IDs logged to $groupsFilePath" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to write Group IDs to file. Error: $_" -ForegroundColor Red
}

# Step 2: Create Conditional Access Policies
Write-Host "`nCreating Conditional Access policies..." -ForegroundColor Cyan

# Get Phishing Resistant MFA Authentication Strength ID
$authStrength = Get-MgPolicyAuthenticationStrengthPolicy | Where-Object { $_.DisplayName -eq "Phishing-resistant MFA" }

if (-not $authStrength) {
    Write-Host "✗ Phishing-resistant MFA authentication strength not found!" -ForegroundColor Red
    exit
}

$policies = @(
    @{ Name = "Phishing Resistant MFA - Windows Enrollment"; Platform = "windows"; GroupName = "Windows Enforcement" },
    @{ Name = "Phishing Resistant MFA - iOS Enrollment"; Platform = "iOS"; GroupName = "iOS Enforcement" },
    @{ Name = "Phishing Resistant MFA - macOS Enrollment"; Platform = "macOS"; GroupName = "MacOS Enforcement" }
)
$policyIds = @{}

foreach ($policy in $policies) {
    try {
        # Check if policy already exists
        $existingPolicy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq '$($policy.Name)'" -ErrorAction SilentlyContinue
        
        if ($existingPolicy) {
            Write-Host "⚠ Policy already exists: $($policy.Name) (ID: $($existingPolicy.Id))" -ForegroundColor Yellow
            Write-Host "  Skipping creation..." -ForegroundColor Gray
            $policyIds[$policy.Name] = $existingPolicy.Id
            continue
        }
        elseif (Test-Path $capFilePath) {
            $existingCAPRecords = Import-Csv -Path $capFilePath -ErrorAction SilentlyContinue
            if ($existingCAPRecords -and $existingCAPRecords.Count -gt 0) {
            Write-Host "⚠ CAP.csv file contains existing policy records. Skipping policy creation to avoid duplicates." -ForegroundColor Yellow
            Write-Host "  If you want to create new policies, please delete or rename the existing CAP.csv file." -ForegroundColor Gray
            continue
            }
        }
        
        $params = @{
            DisplayName = $policy.Name
            State = "enabledForReportingButNotEnforced"
            Conditions = @{
                Applications = @{
                    IncludeApplications = @("All")
                }
                Users = @{
                    IncludeGroups = @($groupIds[$policy.GroupName])
                }
                Platforms = @{
                    IncludePlatforms = @($policy.Platform)
                }
            }
            GrantControls = @{
                Operator = "AND"
                AuthenticationStrength = @{
                    Id = $authStrength.Id
                }
            }
        }

        $newPolicy = New-MgIdentityConditionalAccessPolicy -BodyParameter $params
        $policyIds[$policy.Name] = $newPolicy.Id
        Write-Host "✓ Created policy: $($policy.Name) (ID: $($newPolicy.Id))" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Failed to create policy: $($policy.Name). Error: $_" -ForegroundColor Red
    }
}

# Log Conditional Access Policy IDs to file
Write-Host "`nLogging Conditional Access Policy IDs to file..." -ForegroundColor Cyan
$capFilePath = Join-Path $PSScriptRoot "CAP.csv"
try {
    $capOutput = @()
    foreach ($policyName in $policyIds.Keys) {
        $capOutput += [PSCustomObject]@{
            PolicyName = $policyName
            PolicyId = $policyIds[$policyName]
            CreatedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }
    }
    $capOutput | Export-Csv -Path $capFilePath -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Conditional Access Policy IDs logged to $capFilePath" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to write Conditional Access Policy IDs to file. Error: $_" -ForegroundColor Red
}

# Step 3: Import users from CSV files into respective groups
Write-Host "`nImporting users from CSV files into groups..." -ForegroundColor Cyan

$csvMappings = @(
    @{ Path = Join-Path (Split-Path $PSScriptRoot -Parent) "WorkbookFiles\Windows.csv"; GroupName = "Windows Enforcement" },
    @{ Path = Join-Path (Split-Path $PSScriptRoot -Parent) "WorkbookFiles\iOS.csv"; GroupName = "iOS Enforcement" },
    @{ Path = Join-Path (Split-Path $PSScriptRoot -Parent) "WorkbookFiles\macOS.csv"; GroupName = "macOS Enforcement" }
)

foreach ($mapping in $csvMappings) {
    if (Test-Path $mapping.Path) {
        try {
            $users = Import-Csv -Path $mapping.Path
            $groupId = $groupIds[$mapping.GroupName]
            
            foreach ($user in $users) {
                try {
                    # Assuming CSV has a UserPrincipalName column
                    $mgUser = Get-MgUser -Filter "userPrincipalName eq '$($user.UserPrincipalName)'"
                    if ($mgUser) {
                        # Check if user is already a member of the group
                        $existingMember = Get-MgGroupMember -GroupId $groupId -Filter "id eq '$($mgUser.Id)'" -ErrorAction SilentlyContinue
                        
                        if ($existingMember) {
                            Write-Host "  ⚠ User already in group: $($user.UserPrincipalName) - $($mapping.GroupName)" -ForegroundColor Gray
                        }
                        else {
                            New-MgGroupMember -GroupId $groupId -DirectoryObjectId $mgUser.Id
                            Write-Host "  ✓ Added $($user.UserPrincipalName) to $($mapping.GroupName)" -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Host "  ✗ User not found: $($user.UserPrincipalName)" -ForegroundColor Yellow
                    }
                }
                catch {
                    if ($_.Exception.Message -like "*One or more added object references already exist*") {
                        Write-Host "  ⚠ User already in group: $($user.UserPrincipalName) - $($mapping.GroupName)" -ForegroundColor Gray
                    }
                    else {
                        Write-Host "  ✗ Failed to add $($user.UserPrincipalName) to $($mapping.GroupName). Error: $_" -ForegroundColor Red
                    }
                }
            }
        }
        catch {
            Write-Host "✗ Failed to import from $($mapping.Path). Error: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "✗ CSV file not found: $($mapping.Path)" -ForegroundColor Yellow
    }
}

Write-Host "`nEnrollment Phase setup completed!" -ForegroundColor Green
Write-Host "Note: Policies are in report-only mode. Monitor reports before enforcing." -ForegroundColor Yellow

Disconnect-MgGraph