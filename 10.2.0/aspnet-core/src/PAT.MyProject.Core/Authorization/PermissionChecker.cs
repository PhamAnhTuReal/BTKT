using Abp.Authorization;
using PAT.MyProject.Authorization.Roles;
using PAT.MyProject.Authorization.Users;

namespace PAT.MyProject.Authorization;

public class PermissionChecker : PermissionChecker<Role, User>
{
    public PermissionChecker(UserManager userManager)
        : base(userManager)
    {
    }
}
