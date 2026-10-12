#nullable enable
using System.Collections.Generic;

namespace PAT.MyProject.Exams;

public class ExamPart
{
    public int Id { get; set; }
    public int ExamId { get; set; }
    public byte PartNumber { get; set; }
    public string? Directions { get; set; }

    public Exam Exam { get; set; } = null!;
    public ICollection<QuestionGroup> QuestionGroups { get; set; } = new List<QuestionGroup>();
    public ICollection<Question> Questions { get; set; } = new List<Question>();
}
