using PAT.MyProject.Configuration.Dto;
using System.Threading.Tasks;

namespace PAT.MyProject.Configuration;

public interface IConfigurationAppService
{
    Task ChangeUiTheme(ChangeUiThemeInput input);
}
