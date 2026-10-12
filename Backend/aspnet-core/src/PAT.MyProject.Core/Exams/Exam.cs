#nullable enable
using Abp.Domain.Entities;
using System;
using System.Collections.Generic;

namespace PAT.MyProject.Exams;

public class Exam : Entity<int>
{
    public string Name { get; set; } = string.Empty;
    public int DurationMinutes { get; set; }
    public int TotalQuestions { get; set; }
    public string? Instructions { get; set; }
    public bool IsPublished { get; set; }
    public DateTime CreationTime { get; set; }
    public long? CreatorUserId { get; set; }
    public DateTime? LastModificationTime { get; set; }

    public ICollection<ExamPart> Parts { get; set; } = new List<ExamPart>();
    public ICollection<Question> Questions { get; set; } = new List<Question>();
    public ICollection<ExamAttempt> Attempts { get; set; } = new List<ExamAttempt>();
}
