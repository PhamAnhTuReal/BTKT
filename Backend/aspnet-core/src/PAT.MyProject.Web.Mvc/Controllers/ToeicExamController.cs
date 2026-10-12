#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Abp.AspNetCore.Mvc.Authorization;
using Abp.Domain.Repositories;
using Abp.Domain.Uow;
using Abp.EntityFrameworkCore.Uow;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PAT.MyProject.Controllers;
using PAT.MyProject.EntityFrameworkCore;
using PAT.MyProject.Exams;
using PAT.MyProject.Web.Services;

namespace PAT.MyProject.Web.Controllers;

[AbpMvcAuthorize]
public class ToeicExamController : MyProjectControllerBase
{
    private const long MaxUploadBytes = 20 * 1024 * 1024;
    private readonly IRepository<Exam> _examRepository;
    private readonly ToeicDocxParser _parser;

    public ToeicExamController(IRepository<Exam> examRepository, ToeicDocxParser parser)
    {
        _examRepository = examRepository;
        _parser = parser;
    }

    private Task<Exam?> GetExamForEditing(int id)
    {
        return _examRepository.GetAll()
            .Include(exam => exam.Parts)
                .ThenInclude(part => part.Questions)
                    .ThenInclude(question => question.Options)
            .Include(exam => exam.Parts)
                .ThenInclude(part => part.QuestionGroups)
                    .ThenInclude(group => group.Passages)
            .AsSplitQuery()
            .FirstOrDefaultAsync(exam => exam.Id == id);
    }

    private static ToeicExamEditModel ToEditModel(Exam exam)
    {
        return new ToeicExamEditModel
        {
            Id = exam.Id,
            Name = exam.Name,
            DurationMinutes = exam.DurationMinutes,
            Instructions = exam.Instructions,
            Parts = exam.Parts.OrderBy(part => part.PartNumber).Select(part => new ToeicExamPartEditModel
            {
                Id = part.Id,
                PartNumber = part.PartNumber,
                Directions = part.Directions,
                Groups = part.QuestionGroups.OrderBy(group => group.OrderIndex).Select(group => new ToeicExamGroupEditModel
                {
                    Id = group.Id,
                    FromNumber = group.FromNumber,
                    ToNumber = group.ToNumber,
                    Title = group.Title,
                    Passages = group.Passages.OrderBy(passage => passage.OrderIndex).Select(passage => new ToeicExamPassageEditModel
                    {
                        Id = passage.Id,
                        Content = passage.Content
                    }).ToList()
                }).ToList(),
                Questions = part.Questions.OrderBy(question => question.Number).Select(question => new ToeicExamQuestionEditModel
                {
                    Id = question.Id,
                    Number = question.Number,
                    Content = question.Content,
                    CorrectAnswer = question.CorrectAnswer,
                    Options = question.Options.OrderBy(option => option.Label).Select(option => new ToeicExamOptionEditModel
                    {
                        Id = option.Id,
                        Label = option.Label,
                        Content = option.Content
                    }).ToList()
                }).ToList()
            }).ToList()
        };
    }

    private static bool HasMatchingStructure(Exam exam, ToeicExamEditModel model)
    {
        return HasSameIds(exam.Parts.Select(item => item.Id), model.Parts.Select(item => item.Id)) &&
            exam.Parts.All(part =>
            {
                var partModel = model.Parts.Single(item => item.Id == part.Id);
                return HasSameIds(part.QuestionGroups.Select(item => item.Id), partModel.Groups.Select(item => item.Id)) &&
                    HasSameIds(part.Questions.Select(item => item.Id), partModel.Questions.Select(item => item.Id)) &&
                    part.QuestionGroups.All(group =>
                    {
                        var groupModel = partModel.Groups.Single(item => item.Id == group.Id);
                        return HasSameIds(group.Passages.Select(item => item.Id), groupModel.Passages.Select(item => item.Id));
                    }) &&
                    part.Questions.All(question =>
                    {
                        var questionModel = partModel.Questions.Single(item => item.Id == question.Id);
                        return HasSameIds(question.Options.Select(item => item.Id), questionModel.Options.Select(item => item.Id));
                    });
            });
    }

    private static bool HasSameIds(System.Collections.Generic.IEnumerable<int> existing, System.Collections.Generic.IEnumerable<int> submitted)
    {
        var existingIds = existing.OrderBy(id => id).ToArray();
        var submittedIds = submitted.OrderBy(id => id).ToArray();
        return existingIds.SequenceEqual(submittedIds);
    }

    public ActionResult Index()
    {
        return RedirectToAction("Index", "Home");
    }

    [HttpGet]
    [UnitOfWork]
    public async Task<ActionResult> Edit(int id)
    {
        var exam = await GetExamForEditing(id);
        if (exam == null)
        {
            return NotFound();
        }

        return View(ToEditModel(exam));
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [UnitOfWork]
    [RequestFormLimits(ValueCountLimit = 10000)]
    public async Task<ActionResult> Edit(ToeicExamEditModel model)
    {
        var exam = await GetExamForEditing(model.Id);
        if (exam == null)
        {
            return NotFound();
        }

        if (!HasMatchingStructure(exam, model))
        {
            return BadRequest("Cấu trúc đề đã thay đổi. Hãy tải lại trang chỉnh sửa.");
        }

        if (!ModelState.IsValid)
        {
            return View(model);
        }

        exam.Name = model.Name.Trim();
        exam.DurationMinutes = model.DurationMinutes;
        exam.Instructions = model.Instructions;

        foreach (var part in exam.Parts)
        {
            var partModel = model.Parts.Single(item => item.Id == part.Id);
            part.Directions = partModel.Directions;

            foreach (var group in part.QuestionGroups)
            {
                var groupModel = partModel.Groups.Single(item => item.Id == group.Id);
                group.Title = groupModel.Title;
                foreach (var passage in group.Passages)
                {
                    passage.Content = groupModel.Passages
                        .Single(item => item.Id == passage.Id).Content;
                }
            }

            foreach (var question in part.Questions)
            {
                var questionModel = partModel.Questions.Single(item => item.Id == question.Id);
                question.Content = questionModel.Content;
                question.CorrectAnswer = questionModel.CorrectAnswer;
                foreach (var option in question.Options)
                {
                    option.Content = questionModel.Options
                        .Single(item => item.Id == option.Id).Content;
                }
            }
        }

        await CurrentUnitOfWork.SaveChangesAsync();
        TempData["ToeicExamSuccess"] = $"Đã lưu thay đổi cho đề “{exam.Name}”.";
        return RedirectToAction("Index", "Home");
    }

    [HttpPost]
    [ValidateAntiForgeryToken]
    [UnitOfWork]
    public async Task<ActionResult> Delete(int id)
    {
        var db = CurrentUnitOfWork.GetDbContext<MyProjectDbContext>();
        db.Database.SetCommandTimeout(120);

        var exam = await db.Exams.AsNoTracking().FirstOrDefaultAsync(e => e.Id == id);

        if (exam == null)
        {
            TempData["ToeicExamError"] = "Không tìm thấy đề thi cần xóa.";
            return RedirectToAction("Index", "Home");
        }

        var examName = exam.Name;
        var wasPublished = exam.IsPublished;

        await db.Database.ExecuteSqlInterpolatedAsync($@"
            DELETE aa FROM AttemptAnswers aa
            INNER JOIN ExamAttempts ea ON aa.AttemptId = ea.Id
            WHERE ea.ExamId = {id};

            DELETE aa FROM AttemptAnswers aa
            INNER JOIN Questions q ON aa.QuestionId = q.Id
            WHERE q.ExamId = {id};

            DELETE FROM ExamAttempts WHERE ExamId = {id};

            DELETE qo FROM QuestionOptions qo
            INNER JOIN Questions q ON qo.QuestionId = q.Id
            WHERE q.ExamId = {id};

            DELETE FROM Questions WHERE ExamId = {id};

            DELETE p FROM Passages p
            INNER JOIN QuestionGroups qg ON p.GroupId = qg.Id
            INNER JOIN ExamParts ep ON qg.PartId = ep.Id
            WHERE ep.ExamId = {id};

            DELETE qg FROM QuestionGroups qg
            INNER JOIN ExamParts ep ON qg.PartId = ep.Id
            WHERE ep.ExamId = {id};

            DELETE FROM ExamParts WHERE ExamId = {id};

            DELETE FROM Exams WHERE Id = {id};
        ");

        if (wasPublished)
        {
            var latestExam = await db.Exams
                .OrderByDescending(e => e.CreationTime)
                .FirstOrDefaultAsync();

            if (latestExam != null)
            {
                latestExam.IsPublished = true;
                await db.SaveChangesAsync();
            }
        }

        TempData["ToeicExamSuccess"] = $"Đã xóa thành công đề thi “{examName}”.";
        return RedirectToAction("Index", "Home");
    }

    [HttpPost]
    [UnitOfWork]
    [RequestSizeLimit(MaxUploadBytes)]
    public async Task<ActionResult> Import(IFormFile file)
    {
        if (file == null || file.Length == 0)
        {
            TempData["ToeicExamError"] = "Vui lòng chọn một tệp DOCX.";
            return RedirectToAction("Index", "Home");
        }

        if (file.Length > MaxUploadBytes ||
            !string.Equals(Path.GetExtension(file.FileName), ".docx", StringComparison.OrdinalIgnoreCase))
        {
            TempData["ToeicExamError"] = "Chỉ chấp nhận tệp .docx có dung lượng tối đa 20 MB.";
            return RedirectToAction("Index", "Home");
        }

        ParsedToeicExam parsedExam;
        try
        {
            await using var fileStream = file.OpenReadStream();
            parsedExam = _parser.Parse(fileStream);
        }
        catch (InvalidDataException exception)
        {
            TempData["ToeicExamError"] = exception.Message;
            return RedirectToAction("Index", "Home");
        }
        catch (System.Xml.XmlException)
        {
            TempData["ToeicExamError"] = "Không đọc được cấu trúc DOCX. Hãy kiểm tra tệp và thử tải lại.";
            return RedirectToAction("Index", "Home");
        }
        catch (ArgumentException)
        {
            TempData["ToeicExamError"] = "Tệp DOCX có thuộc tính bị trùng hoặc không hợp lệ.";
            return RedirectToAction("Index", "Home");
        }

        var publishedExams = await _examRepository.GetAll()
            .Where(exam => exam.IsPublished)
            .ToListAsync();
        foreach (var publishedExam in publishedExams)
        {
            publishedExam.IsPublished = false;
        }

        var exam = new Exam
        {
            Name = parsedExam.Name,
            DurationMinutes = parsedExam.DurationMinutes,
            TotalQuestions = parsedExam.Parts.Sum(part => part.Questions.Count),
            Instructions = "Chọn một đáp án cho mỗi câu hỏi. Đề được nhập từ tệp DOCX.",
            IsPublished = true,
            CreationTime = DateTime.Now
        };

        foreach (var parsedPart in parsedExam.Parts)
        {
            var part = new ExamPart
            {
                PartNumber = parsedPart.PartNumber,
                Directions = parsedPart.Directions
            };
            var groupMap = new Dictionary<ParsedToeicGroup, QuestionGroup>();

            foreach (var parsedGroup in parsedPart.Groups)
            {
                var group = new QuestionGroup
                {
                    FromNumber = parsedGroup.FromNumber,
                    ToNumber = parsedGroup.ToNumber,
                    Title = parsedGroup.Title,
                    OrderIndex = parsedGroup.OrderIndex
                };
                foreach (var parsedPassage in parsedGroup.Passages)
                {
                    group.Passages.Add(new Passage
                    {
                        Type = parsedPassage.Type,
                        Content = parsedPassage.Content,
                        OrderIndex = parsedPassage.OrderIndex
                    });
                }

                part.QuestionGroups.Add(group);
                groupMap.Add(parsedGroup, group);
            }

            foreach (var parsedQuestion in parsedPart.Questions)
            {
                var question = new Question
                {
                    Exam = exam,
                    Number = parsedQuestion.Number,
                    Content = parsedQuestion.Content,
                    CorrectAnswer = parsedQuestion.CorrectAnswer,
                    Group = parsedQuestion.Group == null ? null : groupMap[parsedQuestion.Group]
                };
                foreach (var parsedOption in parsedQuestion.Options)
                {
                    question.Options.Add(new QuestionOption
                    {
                        Label = parsedOption.Label,
                        Content = parsedOption.Content
                    });
                }

                part.Questions.Add(question);
            }

            exam.Parts.Add(part);
        }

        await _examRepository.InsertAsync(exam);

        TempData["ToeicExamSuccess"] =
            $"Đã tải đề “{exam.Name}” lên thành công ({exam.TotalQuestions} câu, {exam.DurationMinutes} phút). Đề này hiện được phát hành cho người học.";
        return RedirectToAction("Index", "Home");
    }
}

public sealed class ToeicExamListItem
{
    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public int DurationMinutes { get; set; }
    public int TotalQuestions { get; set; }
    public bool IsPublished { get; set; }
    public DateTime CreationTime { get; set; }
}

public sealed class ToeicExamEditModel
{
    [Microsoft.AspNetCore.Mvc.ModelBinding.Validation.ValidateNever]
    public int Id { get; set; }
    [System.ComponentModel.DataAnnotations.Required]
    [System.ComponentModel.DataAnnotations.StringLength(200)]
    public string Name { get; set; } = string.Empty;
    [System.ComponentModel.DataAnnotations.Range(1, 600)]
    public int DurationMinutes { get; set; }
    public string? Instructions { get; set; }
    public System.Collections.Generic.List<ToeicExamPartEditModel> Parts { get; set; } = new();
}

public sealed class ToeicExamPartEditModel
{
    public int Id { get; set; }
    public byte PartNumber { get; set; }
    public string? Directions { get; set; }
    public System.Collections.Generic.List<ToeicExamGroupEditModel> Groups { get; set; } = new();
    public System.Collections.Generic.List<ToeicExamQuestionEditModel> Questions { get; set; } = new();
}

public sealed class ToeicExamGroupEditModel
{
    public int Id { get; set; }
    public int FromNumber { get; set; }
    public int ToNumber { get; set; }
    public string? Title { get; set; }
    public System.Collections.Generic.List<ToeicExamPassageEditModel> Passages { get; set; } = new();
}

public sealed class ToeicExamPassageEditModel
{
    public int Id { get; set; }
    public string? Content { get; set; }
}

public sealed class ToeicExamQuestionEditModel
{
    public int Id { get; set; }
    public int Number { get; set; }
    [System.ComponentModel.DataAnnotations.Required]
    public string Content { get; set; } = string.Empty;
    [System.ComponentModel.DataAnnotations.Required]
    [System.ComponentModel.DataAnnotations.RegularExpression("^[ABCD]$")]
    public string CorrectAnswer { get; set; } = "A";
    public System.Collections.Generic.List<ToeicExamOptionEditModel> Options { get; set; } = new();
}

public sealed class ToeicExamOptionEditModel
{
    public int Id { get; set; }
    public string Label { get; set; } = string.Empty;
    [System.ComponentModel.DataAnnotations.Required]
    [System.ComponentModel.DataAnnotations.StringLength(1000)]
    public string Content { get; set; } = string.Empty;
}
