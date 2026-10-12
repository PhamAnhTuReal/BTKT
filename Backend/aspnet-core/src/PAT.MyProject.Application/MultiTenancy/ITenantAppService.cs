using Abp.Application.Services;
using PAT.MyProject.MultiTenancy.Dto;

namespace PAT.MyProject.MultiTenancy;

public interface ITenantAppService : IAsyncCrudAppService<TenantDto, int, PagedTenantResultRequestDto, CreateTenantDto, TenantDto>
{
}

