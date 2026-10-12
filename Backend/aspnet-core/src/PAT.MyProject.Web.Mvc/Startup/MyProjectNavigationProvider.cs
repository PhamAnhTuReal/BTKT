using Abp.Application.Navigation;
using Abp.Localization;

namespace PAT.MyProject.Web.Startup;

/// <summary>
/// This class defines menus for the application.
/// </summary>
public class MyProjectNavigationProvider : NavigationProvider
{
    public override void SetNavigation(INavigationProviderContext context)
    {
        context.Manager.MainMenu
            .AddItem(
                new MenuItemDefinition(
                    PageNames.ToeicExams,
                    new FixedLocalizableString("Quản lý đề TOEIC"),
                    url: "",
                    icon: "fas fa-file-upload",
                    requiresAuthentication: true
                )
            );
    }
}