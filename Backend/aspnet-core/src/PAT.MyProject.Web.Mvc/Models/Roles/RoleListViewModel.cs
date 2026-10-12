using PAT.MyProject.Roles.Dto;
using System.Collections.Generic;

namespace PAT.MyProject.Web.Models.Roles;

public class RoleListViewModel
{
    public IReadOnlyList<PermissionDto> Permissions { get; set; }
}
