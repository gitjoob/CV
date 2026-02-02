<#
.SYNOPSIS
    Automated RBAC Group Creation and Access Package Management for Azure Subscriptions

.DESCRIPTION
    This script automates the creation and management of Azure RBAC groups with integrated 
    Entra ID access packages for subscription-level role assignments.
    
    📋 Main Functions:
    1. 🔗 Connects to Azure and Microsoft Graph with required permissions
    2. 👥 Creates RBAC security groups for Reader, Contributor, and Owner roles
    3. 🔐 Enables PIM (Privileged Identity Management) for Owner groups (all environments) 
       and Contributor groups (prod environment only)
    4. 🎯 Assigns Azure RBAC roles at subscription level with user confirmation
    5. 🛡️ Applies ABAC (Attribute-Based Access Control) conditions to Owner role assignments
       to prevent assignment/removal of privileged roles
    6. 📦 Creates and configures Entra ID access packages with environment-aware policies:
       - Reader: Member role, 1/3/6 month policies
       - Contributor Dev/Stg: Member role, 1/3/6 month policies
       - Contributor Prod: Eligible Member role (PIM), 1/3/6 month policies
       - Owner: Eligible Member role (PIM), 8-hour policy
    7. 📊 Automatic catalog resource management with role availability checking
    
    🔐 Security Features:
    - PIM-enabled groups for privileged access (Owner all environments, Contributor prod only)
    - ABAC conditions on Owner roles preventing assignment/deletion of:
      * Owner (8e3af657-a8ff-443c-a75c-2fe8c4bcb635)
      * Contributor (b24988ac-6180-42a0-ab88-20f7382dd24c)
      * User Access Administrator (18d7d88d-d35e-4fb5-a5c3-7773c20a72d9)
      * [Role GUID: f58310d9-a9f6-439a-9e8d-f62e7b41a168]
    - Automatic detection and update of existing Owner assignments lacking ABAC conditions
    
    📝 Naming Conventions:
    - Groups: sg-rbac-{subscription-name}-{Role}
    - Privileged Groups: psg-rbac-{subscription-name}-{Role}
    - Access Packages:
      * "Subscription - {ServiceName} Reader"
      * "Subscription - {ServiceName} Contributor Dev/Stg" (dev/stg only)
      * "Subscription - {ServiceName} Contributor Prod" (prod only)
      * "Subscription - {ServiceName} Owner"
    
    🎯 Environment Detection:
    The script automatically detects environment (dev/stg/prod) from subscription name:
    - Example: "sub-work-dev-01" → environment = "dev"
    - Determines PIM enablement and access package creation accordingly
    
    ⚙️ Required Permissions:
    Microsoft Graph API:
    - Group.ReadWrite.All (create/manage security groups)
    - PrivilegedAccess.ReadWrite.AzureAD (PIM registration)
    - EntitlementManagement.ReadWrite.All (access packages and policies)
    
    Entra ID Directory Roles (at least one required):
    - Identity Governance Administrator (for access package management)
    - Privileged Role Administrator (for PIM operations)
    - Groups Administrator (for group management)
    - Global Administrator (all operations)
    
    Azure RBAC:
    - Owner or User Access Administrator on target subscription (to assign roles)
    
    Catalog Access:
    - Owner or contributor access to Entitlement Management catalogs:
      * Subscriptions catalog ()
      * Subscription Owner catalog ()
    
    📦 Required Modules:
    - Az.Accounts (Azure authentication and subscription management)
    - Az.Resources (Azure RBAC role assignments)
    - Microsoft.Graph.Authentication (Microsoft Graph connection)
    - Microsoft.Graph.Groups (Group operations)
    - Microsoft.Graph.Users (User operations)
    - Microsoft.Graph.Identity.Governance (Entitlement Management)
    
    🔄 Workflow:
    1. User enters subscription name
    2. Script validates all required permissions
    3. Creates three security groups (Reader, Contributor, Owner)
    4. Registers Contributor (prod only) and Owner groups for PIM
    5. Prompts for Azure RBAC role assignments with ABAC conditions for Owner
    6. Creates/updates access packages with environment-appropriate policies
    7. Adds groups to access packages with correct role type (Member vs Eligible Member)
    
    ⚠️ Important Notes:
    - ABAC conditions are applied only to subscription-level Owner role assignments
    - PIM registration is idempotent and safe to run multiple times
    - Existing Owner assignments without ABAC conditions will prompt for update
    - Access package policies include manager approval requirements
    - Catalog role propagation may take a few seconds after adding PIM groups

.PARAMETER subname
    The name of the Azure subscription (prompted at runtime)
    Example: "sub-onsite-prod-02"

.EXAMPLE
    .\Create-rbac-Groups.ps1
    
    Prompts for subscription name and creates all required groups, role assignments,
    and access packages with appropriate configurations.

.NOTES
    Created by: Johan Öberg
    Last Updated: January 2026
    Version: 3.0
    Tenant ID: 
    
    Change Log:
    - v3.0: Added ABAC conditions for Owner role assignments
    - v2.0: Added PIM registration and access package management
    - v1.0: Initial version with basic group creation
#>