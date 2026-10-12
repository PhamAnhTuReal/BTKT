using Abp.AspNetCore.Mvc.Authorization;
using PAT.MyProject.Controllers;
using Microsoft.AspNetCore.Mvc;

namespace PAT.MyProject.Web.Controllers;

[AbpMvcAuthorize]
public class HomeController : MyProjectControllerBase
{
    public ActionResult Index()
    {
        return View();
    }
}
