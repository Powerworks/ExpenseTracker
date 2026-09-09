namespace CratisApp.Expenses.Approval.SubmitExpense;

using Cratis.Chronicle.Events;

public record ExpenseId(Guid Value) : EventSourceId<Guid>(Value)
{
    public static readonly ExpenseId NotSet = new(Guid.Empty);

    public static ExpenseId New() => new(Guid.NewGuid());

    public static implicit operator ExpenseId(Guid value) => new(value);
}
