using PAT.MyProject.Roles.Dto;
using System.Collections.Generic;

namespace PAT.MyProject.Web.Models.Users;

public class UserListViewModel
{
    public IReadOnlyList<RoleDto> Roles { get; set; }
}
