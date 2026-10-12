using Abp.AspNetCore.Mvc.Authorization;
using Abp.Domain.Repositories;
using Microsoft.EntityFrameworkCore;
using PAT.MyProject.Controllers;
using PAT.MyProject.Exams;
using Microsoft.AspNetCore.Mvc;
using System.Linq;
using System.Threading.Tasks;

namespace PAT.MyProject.Web.Controllers;

[AbpMvcAuthorize]
public class HomeController : MyProjectControllerBase
{
    private readonly IRepository<Exam> _examRepository;

    public HomeController(IRepository<Exam> examRepository)
    {
        _examRepository = examRepository;
    }

    public async Task<ActionResult> Index()
    {
        var exams = await _examRepository.GetAll()
            .AsNoTracking()
            .OrderByDescending(exam => exam.CreationTime)
            .Select(exam => new ToeicExamListItem
            {
                Id = exam.Id,
                Name = exam.Name,
                DurationMinutes = exam.DurationMinutes,
                TotalQuestions = exam.TotalQuestions,
                IsPublished = exam.IsPublished,
                CreationTime = exam.CreationTime
            })
            .ToListAsync();

        return View(exams);
    }
}
