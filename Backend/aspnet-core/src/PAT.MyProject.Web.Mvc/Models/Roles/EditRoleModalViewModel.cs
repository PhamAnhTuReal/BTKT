using Abp.AutoMapper;
using PAT.MyProject.Roles.Dto;
using PAT.MyProject.Web.Models.Common;

namespace PAT.MyProject.Web.Models.Roles;

[AutoMapFrom(typeof(GetRoleForEditOutput))]
public class EditRoleModalViewModel : GetRoleForEditOutput, IPermissionsEditViewModel
{
    public bool HasPermission(FlatPermissionDto permission)
    {
        return GrantedPermissionNames.Contains(permission.Name);
    }
}
