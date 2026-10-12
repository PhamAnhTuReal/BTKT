using Abp.Modules;
using Abp.Reflection.Extensions;
using PAT.MyProject.Configuration;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;

namespace PAT.MyProject.Web.Startup;

[DependsOn(typeof(MyProjectWebCoreModule))]
public class MyProjectWebMvcModule : AbpModule
{
    private readonly IWebHostEnvironment _env;
    private readonly IConfigurationRoot _appConfiguration;

    public MyProjectWebMvcModule(IWebHostEnvironment env)
    {
        _env = env;
        _appConfiguration = env.GetAppConfiguration();
    }

    public override void PreInitialize()
    {
        Configuration.Navigation.Providers.Add<MyProjectNavigationProvider>();
    }

    public override void Initialize()
    {
        IocManager.RegisterAssemblyByConvention(typeof(MyProjectWebMvcModule).GetAssembly());
    }
}
