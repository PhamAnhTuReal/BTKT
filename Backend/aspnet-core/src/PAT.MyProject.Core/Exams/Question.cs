#nullable enable
using System.Collections.Generic;

namespace PAT.MyProject.Exams;

public class Question
{
    public int Id { get; set; }
    public int ExamId { get; set; }
    public int PartId { get; set; }
    public int? GroupId { get; set; }
    public int Number { get; set; }
    public string Content { get; set; } = string.Empty;
    public string CorrectAnswer { get; set; } = string.Empty;
    public string? Explanation { get; set; }

    public Exam Exam { get; set; } = null!;
    public ExamPart Part { get; set; } = null!;
    public QuestionGroup? Group { get; set; }
    public ICollection<QuestionOption> Options { get; set; } = new List<QuestionOption>();
    public ICollection<AttemptAnswer> AttemptAnswers { get; set; } = new List<AttemptAnswer>();
}
