#nullable enable
using System.Collections.Generic;

namespace PAT.MyProject.Exams;

public class QuestionGroup
{
    public int Id { get; set; }
    public int PartId { get; set; }
    public int FromNumber { get; set; }
    public int ToNumber { get; set; }
    public string? Title { get; set; }
    public int OrderIndex { get; set; }

    public ExamPart Part { get; set; } = null!;
    public ICollection<Passage> Passages { get; set; } = new List<Passage>();
    public ICollection<Question> Questions { get; set; } = new List<Question>();
}
