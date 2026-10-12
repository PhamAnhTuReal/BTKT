using Abp.Zero.EntityFrameworkCore;
using PAT.MyProject.Authorization.Roles;
using PAT.MyProject.Authorization.Users;
using PAT.MyProject.Exams;
using PAT.MyProject.MultiTenancy;
using Microsoft.EntityFrameworkCore;

namespace PAT.MyProject.EntityFrameworkCore;

public class MyProjectDbContext : AbpZeroDbContext<Tenant, Role, User, MyProjectDbContext>
{
    public DbSet<Exam> Exams => Set<Exam>();
    public DbSet<ExamPart> ExamParts => Set<ExamPart>();
    public DbSet<QuestionGroup> QuestionGroups => Set<QuestionGroup>();
    public DbSet<Passage> Passages => Set<Passage>();
    public DbSet<Question> Questions => Set<Question>();
    public DbSet<QuestionOption> QuestionOptions => Set<QuestionOption>();
    public DbSet<ExamAttempt> ExamAttempts => Set<ExamAttempt>();
    public DbSet<AttemptAnswer> AttemptAnswers => Set<AttemptAnswer>();

    public MyProjectDbContext(DbContextOptions<MyProjectDbContext> options)
        : base(options)
    {
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Exam>(entity =>
        {
            entity.ToTable("Exams", table =>
                table.HasCheckConstraint("CK_Exams_Duration", "[DurationMinutes] > 0"));
            entity.HasKey(x => x.Id).HasName("PK_Exams");
            entity.Property(x => x.Name).HasMaxLength(200).IsRequired();
            entity.Property(x => x.DurationMinutes).HasDefaultValue(75);
            entity.Property(x => x.TotalQuestions).HasDefaultValue(100);
            entity.Property(x => x.Instructions).HasColumnType("nvarchar(max)");
            entity.Property(x => x.IsPublished).HasDefaultValue(false);
            entity.Property(x => x.CreationTime).HasColumnType("datetime2").HasDefaultValueSql("SYSUTCDATETIME()");
            entity.Property(x => x.CreatorUserId).HasColumnType("bigint");
            entity.Property(x => x.LastModificationTime).HasColumnType("datetime2");
        });

        modelBuilder.Entity<ExamPart>(entity =>
        {
            entity.ToTable("ExamParts", table =>
                table.HasCheckConstraint("CK_ExamParts_Part", "[PartNumber] IN (5,6,7)"));
            entity.HasKey(x => x.Id).HasName("PK_ExamParts");
            entity.Property(x => x.PartNumber).HasColumnType("tinyint");
            entity.Property(x => x.Directions).HasColumnType("nvarchar(max)");
            entity.HasIndex(x => new { x.ExamId, x.PartNumber }).IsUnique().HasDatabaseName("UQ_ExamParts");
            entity.HasOne(x => x.Exam).WithMany(x => x.Parts)
                .HasForeignKey(x => x.ExamId).OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("FK_ExamParts_Exams");
        });

        modelBuilder.Entity<QuestionGroup>(entity =>
        {
            entity.ToTable("QuestionGroups", table =>
                table.HasCheckConstraint("CK_QG_Range", "[FromNumber] <= [ToNumber]"));
            entity.HasKey(x => x.Id).HasName("PK_QuestionGroups");
            entity.Property(x => x.Title).HasMaxLength(500);
            entity.Property(x => x.OrderIndex).HasDefaultValue(0);
            entity.HasOne(x => x.Part).WithMany(x => x.QuestionGroups)
                .HasForeignKey(x => x.PartId).OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("FK_QuestionGroups_Parts");
        });

        modelBuilder.Entity<Passage>(entity =>
        {
            entity.ToTable("Passages");
            entity.HasKey(x => x.Id).HasName("PK_Passages");
            entity.Property(x => x.Type).HasMaxLength(100);
            entity.Property(x => x.Content).HasColumnType("nvarchar(max)");
            entity.Property(x => x.ImageUrl).HasMaxLength(500);
            entity.Property(x => x.OrderIndex).HasDefaultValue(0);
            entity.HasOne(x => x.Group).WithMany(x => x.Passages)
                .HasForeignKey(x => x.GroupId).OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("FK_Passages_Groups");
        });

        modelBuilder.Entity<Question>(entity =>
        {
            entity.ToTable("Questions", table =>
                table.HasCheckConstraint("CK_Questions_Answer", "[CorrectAnswer] IN ('A','B','C','D')"));
            entity.HasKey(x => x.Id).HasName("PK_Questions");
            entity.Property(x => x.Content).HasColumnType("nvarchar(max)").IsRequired();
            entity.Property(x => x.CorrectAnswer).HasColumnType("char(1)").IsRequired();
            entity.Property(x => x.Explanation).HasColumnType("nvarchar(max)");
            entity.HasIndex(x => new { x.ExamId, x.Number }).IsUnique().HasDatabaseName("UQ_Questions_Number");
            entity.HasIndex(x => x.PartId).HasDatabaseName("IX_Questions_Part");
            entity.HasIndex(x => x.GroupId).HasDatabaseName("IX_Questions_Group");
            entity.HasOne(x => x.Exam).WithMany(x => x.Questions)
                .HasForeignKey(x => x.ExamId).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_Questions_Exams");
            entity.HasOne(x => x.Part).WithMany(x => x.Questions)
                .HasForeignKey(x => x.PartId).OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("FK_Questions_Parts");
            entity.HasOne(x => x.Group).WithMany(x => x.Questions)
                .HasForeignKey(x => x.GroupId).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_Questions_Groups");
        });

        modelBuilder.Entity<QuestionOption>(entity =>
        {
            entity.ToTable("QuestionOptions", table =>
                table.HasCheckConstraint("CK_Options_Label", "[Label] IN ('A','B','C','D')"));
            entity.HasKey(x => x.Id).HasName("PK_QuestionOptions");
            entity.Property(x => x.Label).HasColumnType("char(1)").IsRequired();
            entity.Property(x => x.Content).HasMaxLength(1000).IsRequired();
            entity.HasIndex(x => new { x.QuestionId, x.Label }).IsUnique().HasDatabaseName("UQ_Options");
            entity.HasOne(x => x.Question).WithMany(x => x.Options)
                .HasForeignKey(x => x.QuestionId).OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("FK_Options_Questions");
        });

        modelBuilder.Entity<ExamAttempt>(entity =>
        {
            entity.ToTable("ExamAttempts", table =>
                table.HasCheckConstraint("CK_Attempts_Status", "[Status] IN (0,1,2)"));
            entity.HasKey(x => x.Id).HasName("PK_ExamAttempts");
            entity.Property(x => x.UserId).HasColumnType("bigint");
            entity.Property(x => x.StartTime).HasColumnType("datetime2").HasDefaultValueSql("SYSUTCDATETIME()");
            entity.Property(x => x.SubmitTime).HasColumnType("datetime2");
            entity.Property(x => x.Status).HasColumnType("tinyint").HasDefaultValue((byte)0);
            entity.HasIndex(x => new { x.UserId, x.ExamId }).HasDatabaseName("IX_Attempts_User");
            entity.HasOne(x => x.Exam).WithMany(x => x.Attempts)
                .HasForeignKey(x => x.ExamId).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_Attempts_Exams");
            entity.HasOne(x => x.User).WithMany()
                .HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_Attempts_AbpUsers");
        });

        modelBuilder.Entity<AttemptAnswer>(entity =>
        {
            entity.ToTable("AttemptAnswers", table =>
                table.HasCheckConstraint(
                    "CK_Answers_Option",
                    "[SelectedOption] IS NULL OR [SelectedOption] IN ('A','B','C','D')"));
            entity.HasKey(x => x.Id).HasName("PK_AttemptAnswers");
            entity.Property(x => x.SelectedOption).HasColumnType("char(1)");
            entity.HasIndex(x => new { x.AttemptId, x.QuestionId }).IsUnique().HasDatabaseName("UQ_Answers");
            entity.HasOne(x => x.Attempt).WithMany(x => x.Answers)
                .HasForeignKey(x => x.AttemptId).OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("FK_Answers_Attempts");
            entity.HasOne(x => x.Question).WithMany(x => x.AttemptAnswers)
                .HasForeignKey(x => x.QuestionId).OnDelete(DeleteBehavior.NoAction)
                .HasConstraintName("FK_Answers_Questions");
        });
    }
}
