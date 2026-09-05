namespace CratisApp.Expenses.Approval.RejectExpense;

using Cratis.Arc.Commands.ModelBound;
using Cratis.Chronicle.Events;
using Cratis.Chronicle.Keys;
using Cratis.Monads;
using CratisApp.Expenses.Approval.ApproveExpense;

[Command]
public record RejectExpense([Key] Guid ExpenseId, string RejectedBy)
{
    public Result<ExpenseRejected, string> Handle(ExpenseStatus? current)
    {
        if (current is null || current.Status != "PendingApproval")
        {
            return "Expense is not pending approval";
        }

        return new ExpenseRejected(RejectedBy);
    }
}

[EventType]
public record ExpenseRejected(string RejectedBy);
