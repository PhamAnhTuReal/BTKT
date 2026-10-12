using Abp.Application.Services;
using PAT.MyProject.Sessions.Dto;
using System.Threading.Tasks;

namespace PAT.MyProject.Sessions;

public interface ISessionAppService : IApplicationService
{
    Task<GetCurrentLoginInformationsOutput> GetCurrentLoginInformations();
}
