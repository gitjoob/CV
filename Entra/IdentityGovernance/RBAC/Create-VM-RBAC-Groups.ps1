<#
.SYNOPSIS
    Automated RBAC Group Creation and Access Package Management for Azure Virtual Machines

.DESCRIPTION
    This script automates the creation and management of Azure RBAC groups with integrated 
    Entra ID access packages for VM-level access assignments.
    
    📋 Main Functions:
    1. 🔗 Connects to Azure and Microsoft Graph (detects runbook vs local execution)
    2. ✅ Validates VM exists and is accessible
    3. 🔐 Validates required permissions (Groups Administrator, Privileged Role Administrator)
    4. 👥 Creates RBAC security groups for VM access:
       - Users group: Normal security group for standard VM users
       - Admins group: Privileged security group (IsAssignableToRole) for VM administrators
    5. 📁 Creates or validates "Virtual Machines" access package catalog
    6. 📦 Creates and configures Entra ID access packages:
       - Users Access Package: 1 Year, 6 Month, 1 Month policies
       - Admins Access Package: 1 Month policy only
    7. 🔗 Adds groups as resources to respective access packages
    
    🔐 Security Features:
    - PIM-enabled groups for administrative access (IsAssignableToRole)
    - Two-stage approval process with manager and team approval
    - Automatic access expiration with configurable durations
    - Fallback reviewers for approval workflow
    
    📝 Naming Conventions:
    - Groups: grp-rbac-vm-{vm-name}-{Users|Admins}
    - Catalog: "Virtual Machines"
    - Access Packages:
      * "Virtual Machine - {vm-name} - Users"
      * "Virtual Machine - {vm-name} - Admins"
    
    ⚙️ Required Permissions:
    Microsoft Graph API:
    - Group.ReadWrite.All (create/manage security groups)
    - PrivilegedAccess.ReadWrite.AzureAD (PIM registration)
    - EntitlementManagement.ReadWrite.All (access packages and policies)
    
    Entra ID Directory Roles (required):
    - Groups Administrator (for group management including privileged groups)
    - Privileged Role Administrator (for PIM operations)
    
    Azure RBAC:
    - Reader access to the resource group or subscription containing the VM
    
    📦 Required Modules:
    - Az.Accounts (Azure authentication and VM validation)
    - Az.Compute (VM operations)
    - Microsoft.Graph.Authentication (Microsoft Graph connection)
    - Microsoft.Graph.Groups (Group operations)
    - Microsoft.Graph.Users (User operations)
    - Microsoft.Graph.Identity.Governance (Entitlement Management)
    
    🔄 Workflow:
    1. Detects execution context (runbook vs local)
    2. Connects to Azure and Microsoft Graph appropriately
    3. Validates VM exists
    4. Validates user permissions
    5. Creates Users and Admins groups
    6. Creates or validates "Virtual Machines" catalog
    7. Adds groups to catalog
    8. Creates Users access package with 1 Year, 6 Month, 1 Month policies
    9. Creates Admins access package with 1 Month policy
    10. Adds groups as resources to access packages
    
    ⚠️ Important Notes:
    - Admins group is created as privileged (IsAssignableToRole)
    - Access packages require two-stage approval (manager + team)
    - 1 Month policy does not allow extension
    - Script is idempotent - safe to run multiple times

.PARAMETER VM
    The name of the Azure Virtual Machine.
    Example: "vm-cloudockit", "vm-webapp-prod-01"

.EXAMPLE
    .\Create-vm-rbac-Groups.ps1 -VM "vm-cloudockit"
    
    Creates RBAC groups and access packages for vm-cloudockit.

.EXAMPLE
    .\Create-vm-rbac-Groups.ps1 -VM "vm-webapp-prod-01"
    
    Creates RBAC groups and access packages for vm-webapp-prod-01.

.NOTES
    Created by: Johan Öberg
    Last Updated: January 2026
    Version: 1.0
    Tenant ID: 
    
    Change Log:
    - v1.0: Initial version with VM RBAC group and access package automation
#>
