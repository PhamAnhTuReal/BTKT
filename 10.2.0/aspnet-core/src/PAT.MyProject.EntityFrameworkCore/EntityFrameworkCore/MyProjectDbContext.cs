using Abp.Zero.EntityFrameworkCore;
using PAT.MyProject.Authorization.Roles;
using PAT.MyProject.Authorization.Users;
using PAT.MyProject.MultiTenancy;
using Microsoft.EntityFrameworkCore;

namespace PAT.MyProject.EntityFrameworkCore;

public class MyProjectDbContext : AbpZeroDbContext<Tenant, Role, User, MyProjectDbContext>
{
    /* Define a DbSet for each entity of the application */

    public MyProjectDbContext(DbContextOptions<MyProjectDbContext> options)
        : base(options)
    {
    }
}
