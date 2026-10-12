using System;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Abp.Domain.Repositories;
using Abp.Domain.Uow;
using Abp.EntityFrameworkCore.Uow;
using Abp.Web.Security.AntiForgery;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PAT.MyProject.Controllers;
using PAT.MyProject.EntityFrameworkCore;
using PAT.MyProject.Exams;

namespace PAT.MyProject.Web.Host.Controllers
{
    [ApiController]
    [AllowAnonymous]
    [IgnoreAntiforgeryToken]
    [Route("api/exams")]
    public class ExamsController : MyProjectControllerBase
    {
        private readonly IRepository<Exam> _examRepository;

        public ExamsController(IRepository<Exam> examRepository)
        {
            _examRepository = examRepository;
        }

        [HttpGet("published")]
        [UnitOfWork]
        public async Task<ActionResult<PublishedExamDto>> GetPublished()
        {
            var exam = await _examRepository.GetAll()
                .AsNoTracking()
                .AsSplitQuery()
                .Where(candidate => candidate.IsPublished)
                .OrderByDescending(candidate => candidate.CreationTime)
                .Include(candidate => candidate.Parts)
                    .ThenInclude(part => part.Questions)
                        .ThenInclude(question => question.Options)
                .Include(candidate => candidate.Parts)
                    .ThenInclude(part => part.QuestionGroups)
                        .ThenInclude(group => group.Passages)
                .FirstOrDefaultAsync();

            if (exam == null)
            {
                return NotFound(new { message = "Hiện chưa có đề thi TOEIC nào được phát hành." });
            }

            return Ok(new PublishedExamDto
            {
                Id = exam.Id,
                Name = exam.Name,
                DurationMinutes = exam.DurationMinutes,
                TotalQuestions = exam.TotalQuestions,
                Instructions = exam.Instructions,
                Parts = exam.Parts
                    .OrderBy(part => part.PartNumber)
                    .Select(part => new PublishedExamPartDto
                    {
                        PartNumber = part.PartNumber,
                        Directions = part.Directions,
                        Groups = part.QuestionGroups
                            .OrderBy(group => group.OrderIndex)
                            .Select(group => new PublishedExamGroupDto
                            {
                                FromNumber = group.FromNumber,
                                ToNumber = group.ToNumber,
                                Title = group.Title,
                                Passages = group.Passages
                                    .OrderBy(passage => passage.OrderIndex)
                                    .Select(passage => new PublishedExamPassageDto
                                    {
                                        Type = passage.Type,
                                        Content = passage.Content
                                    })
                                    .ToList()
                            })
                            .ToList(),
                        Questions = part.Questions
                            .OrderBy(question => question.Number)
                            .Select(question => new PublishedExamQuestionDto
                            {
                                Id = question.Id,
                                Number = question.Number,
                                Content = question.Content,
                                CorrectAnswer = question.CorrectAnswer,
                                Options = question.Options
                                    .OrderBy(option => option.Label)
                                    .Select(option => new PublishedExamOptionDto
                                    {
                                        Label = option.Label,
                                        Content = option.Content
                                    })
                                    .ToList()
                            })
                            .ToList()
                    })
                    .ToList()
            });
        }

        [HttpPost("submit")]
        [UnitOfWork]
        public async Task<ActionResult<SubmitExamResultDto>> Submit([FromBody] SubmitExamInputDto input)
        {
            var db = CurrentUnitOfWork.GetDbContext<MyProjectDbContext>();

            Exam exam = null;
            if (input != null && input.ExamId.HasValue && input.ExamId.Value > 0)
            {
                exam = await db.Exams
                    .Include(e => e.Questions)
                    .FirstOrDefaultAsync(e => e.Id == input.ExamId.Value);
            }

            if (exam == null)
            {
                exam = await db.Exams
                    .Include(e => e.Questions)
                    .Where(e => e.IsPublished)
                    .OrderByDescending(e => e.CreationTime)
                    .FirstOrDefaultAsync();
            }

            if (exam == null)
            {
                return NotFound(new { message = "Không tìm thấy đề thi tương ứng." });
            }

            var userId = AbpSession.UserId ?? await db.Users.IgnoreQueryFilters().Select(u => u.Id).FirstOrDefaultAsync();

            int correctCount = 0;
            int incorrectCount = 0;
            int skippedCount = 0;

            var answerMap = input?.Answers ?? new Dictionary<string, string>();

            var attempt = new ExamAttempt
            {
                ExamId = exam.Id,
                UserId = userId,
                StartTime = DateTime.UtcNow.AddSeconds(-(input?.SecondsTaken ?? 0)),
                SubmitTime = DateTime.UtcNow,
                Status = 1
            };

            db.ExamAttempts.Add(attempt);
            await db.SaveChangesAsync();

            foreach (var question in exam.Questions.OrderBy(q => q.Number))
            {
                string selectedOption = null;
                if (answerMap.TryGetValue(question.Number.ToString(), out var choice) && !string.IsNullOrWhiteSpace(choice))
                {
                    var trimmed = choice.Trim().ToUpperInvariant();
                    if (trimmed == "A" || trimmed == "B" || trimmed == "C" || trimmed == "D")
                    {
                        selectedOption = trimmed;
                    }
                }

                bool? isCorrect = null;
                if (selectedOption != null)
                {
                    var correct = question.CorrectAnswer?.Trim().ToUpperInvariant();
                    isCorrect = (!string.IsNullOrEmpty(correct) && selectedOption == correct);
                    if (isCorrect == true)
                    {
                        correctCount++;
                    }
                    else
                    {
                        incorrectCount++;
                    }
                }
                else
                {
                    skippedCount++;
                }

                db.AttemptAnswers.Add(new AttemptAnswer
                {
                    AttemptId = attempt.Id,
                    QuestionId = question.Id,
                    SelectedOption = selectedOption,
                    IsCorrect = isCorrect
                });
            }

            attempt.CorrectCount = correctCount;
            attempt.WrongCount = incorrectCount;
            attempt.SkippedCount = skippedCount;

            await db.SaveChangesAsync();

            var totalQuestions = exam.TotalQuestions > 0 ? exam.TotalQuestions : exam.Questions.Count;
            var score = CalculateReadingScore(correctCount, totalQuestions);

            return Ok(new SubmitExamResultDto
            {
                AttemptId = attempt.Id,
                ExamId = exam.Id,
                TotalQuestions = totalQuestions,
                CorrectCount = correctCount,
                IncorrectCount = incorrectCount,
                SkippedCount = skippedCount,
                Score = score,
                SubmitTime = attempt.SubmitTime ?? DateTime.UtcNow
            });
        }

        private static int CalculateReadingScore(int correctCount, int totalCount)
        {
            if (totalCount == 0 || correctCount <= 0) return 5;
            if (correctCount >= totalCount) return 495;

            int[] rawThresholds = { 0, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100 };
            int[] scaledScores = { 5, 5, 35, 60, 95, 125, 160, 195, 225, 255, 280, 305, 325, 350, 375, 410, 445, 475, 495 };

            var normalizedRaw = (int)Math.Round((double)correctCount * 100 / totalCount);
            if (normalizedRaw < 0) normalizedRaw = 0;
            if (normalizedRaw > 100) normalizedRaw = 100;

            for (int i = 0; i < rawThresholds.Length - 1; i++)
            {
                int r0 = rawThresholds[i];
                int r1 = rawThresholds[i + 1];
                if (normalizedRaw >= r0 && normalizedRaw <= r1)
                {
                    int s0 = scaledScores[i];
                    int s1 = scaledScores[i + 1];
                    if (r1 == r0) return s0;
                    double t = (double)(normalizedRaw - r0) / (r1 - r0);
                    int val = (int)Math.Round(s0 + t * (s1 - s0));
                    return ((val + 2) / 5) * 5;
                }
            }

            return 495;
        }
    }

    public sealed class PublishedExamDto
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public int DurationMinutes { get; set; }
        public int TotalQuestions { get; set; }
        public string Instructions { get; set; }
        public List<PublishedExamPartDto> Parts { get; set; } = new List<PublishedExamPartDto>();
    }

    public sealed class PublishedExamPartDto
    {
        public byte PartNumber { get; set; }
        public string Directions { get; set; }
        public List<PublishedExamGroupDto> Groups { get; set; } = new List<PublishedExamGroupDto>();
        public List<PublishedExamQuestionDto> Questions { get; set; } = new List<PublishedExamQuestionDto>();
    }

    public sealed class PublishedExamGroupDto
    {
        public int FromNumber { get; set; }
        public int ToNumber { get; set; }
        public string Title { get; set; }
        public List<PublishedExamPassageDto> Passages { get; set; } = new List<PublishedExamPassageDto>();
    }

    public sealed class PublishedExamPassageDto
    {
        public string Type { get; set; }
        public string Content { get; set; }
    }

    public sealed class PublishedExamQuestionDto
    {
        public int Id { get; set; }
        public int Number { get; set; }
        public string Content { get; set; }
        public string CorrectAnswer { get; set; }
        public List<PublishedExamOptionDto> Options { get; set; } = new List<PublishedExamOptionDto>();
    }

    public sealed class PublishedExamOptionDto
    {
        public string Label { get; set; }
        public string Content { get; set; }
    }

    public sealed class SubmitExamInputDto
    {
        public int? ExamId { get; set; }
        public int? SecondsTaken { get; set; }
        public Dictionary<string, string> Answers { get; set; } = new Dictionary<string, string>();
    }

    public sealed class SubmitExamResultDto
    {
        public int AttemptId { get; set; }
        public int ExamId { get; set; }
        public int TotalQuestions { get; set; }
        public int CorrectCount { get; set; }
        public int IncorrectCount { get; set; }
        public int SkippedCount { get; set; }
        public int Score { get; set; }
        public DateTime SubmitTime { get; set; }
    }
}
