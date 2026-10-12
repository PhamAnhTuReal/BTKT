#nullable enable
namespace PAT.MyProject.Exams;

public class AttemptAnswer
{
    public int Id { get; set; }
    public int AttemptId { get; set; }
    public int QuestionId { get; set; }
    public string? SelectedOption { get; set; }
    public bool? IsCorrect { get; set; }

    public ExamAttempt Attempt { get; set; } = null!;
    public Question Question { get; set; } = null!;
}
