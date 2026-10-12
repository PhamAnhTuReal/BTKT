using PAT.MyProject.Roles.Dto;
using System.Collections.Generic;

namespace PAT.MyProject.Web.Models.Common;

public interface IPermissionsEditViewModel
{
    List<FlatPermissionDto> Permissions { get; set; }
}