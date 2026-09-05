namespace CratisApp.Expenses.Approval.SubmitExpense;

using Cratis.Arc.Commands;
using Cratis.Chronicle.Events;
using Cratis.Chronicle.Reactors;
using CratisApp.Expenses.Approval.ApproveExpense;
using FluentValidation;
using Microsoft.Extensions.Configuration;

[Command]
public record SubmitExpense(decimal Amount, string Description)
{
    public (Guid, ExpenseSubmitted) Handle()
    {
        var eventSourceId = Guid.NewGuid();

        return (eventSourceId, new(Amount, Description));
    }
}

[EventType]
public record ExpenseSubmitted(decimal Amount, string Description);

public class SubmitExpenseValidator : CommandValidator<SubmitExpense>
{
    public SubmitExpenseValidator()
    {
        RuleFor(c => c.Amount).GreaterThan(0).WithMessage("Amount must be greater than zero");
        RuleFor(c => c.Description).NotEmpty().WithMessage("Description is required");
    }
}

public class AutoApprovalReactor(IConfiguration configuration, ICommandPipeline commands) : IReactor
{
    [OnceOnly]
    public async Task Handle(ExpenseSubmitted @event, EventContext context)
    {
        var requireApprovalGate = configuration.GetValue("ExpensePolicy:RequireApprovalGate", true);
        var autoApprovalThreshold = configuration.GetValue("ExpensePolicy:AutoApprovalThreshold", 100.00m);

        if (!requireApprovalGate || @event.Amount < autoApprovalThreshold)
        {
            var reason = !requireApprovalGate ? "AutoNoGate" : "AutoThreshold";
            var expenseId = Guid.Parse(context.EventSourceId.Value);

            // Hard rule: NEVER write ExpenseApproved directly from a reactor.
            // State changes must always go through the command pipeline to ensure business rules and validation are respected.
            await commands.Execute(new ApproveExpense(expenseId, "system", reason));
        }
    }
}
