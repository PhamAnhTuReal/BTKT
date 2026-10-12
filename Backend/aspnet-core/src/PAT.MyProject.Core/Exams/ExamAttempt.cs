#nullable enable
using System;
using System.Collections.Generic;
using PAT.MyProject.Authorization.Users;

namespace PAT.MyProject.Exams;

public class ExamAttempt
{
    public int Id { get; set; }
    public int ExamId { get; set; }
    public long UserId { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime? SubmitTime { get; set; }
    public byte Status { get; set; }
    public int? CorrectCount { get; set; }
    public int? WrongCount { get; set; }
    public int? SkippedCount { get; set; }

    public Exam Exam { get; set; } = null!;
    public User User { get; set; } = null!;
    public ICollection<AttemptAnswer> Answers { get; set; } = new List<AttemptAnswer>();
}
