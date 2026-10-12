#nullable enable
namespace PAT.MyProject.Exams;

public class Passage
{
    public int Id { get; set; }
    public int GroupId { get; set; }
    public string? Type { get; set; }
    public string? Content { get; set; }
    public string? ImageUrl { get; set; }
    public int OrderIndex { get; set; }

    public QuestionGroup Group { get; set; } = null!;
}
