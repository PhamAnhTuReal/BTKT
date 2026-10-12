using Abp.AutoMapper;
using PAT.MyProject.Sessions.Dto;

namespace PAT.MyProject.Web.Views.Shared.Components.TenantChange;

[AutoMapFrom(typeof(GetCurrentLoginInformationsOutput))]
public class TenantChangeViewModel
{
    public TenantLoginInfoDto Tenant { get; set; }
}
