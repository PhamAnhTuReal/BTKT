using Abp.MultiTenancy;
using PAT.MyProject.Authorization.Users;

namespace PAT.MyProject.MultiTenancy;

public class Tenant : AbpTenant<User>
{
    public Tenant()
    {
    }

    public Tenant(string tenancyName, string name)
        : base(tenancyName, name)
    {
    }
}
