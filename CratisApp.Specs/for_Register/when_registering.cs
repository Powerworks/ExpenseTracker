using Cratis.Specifications;
using CratisApp.SomeModule.SomeFeature;
using CratisApp.SomeModule.SomeFeature.Registration;

namespace CratisApp.Specs.for_Register;

public class when_registering : Specification
{
    Register _command = null!;
    Registered _event = null!;

    void Establish() => _command = new(new SomeName("Ada"));
    void Because() => (_, _event) = _command.Handle();

    [Fact] void should_carry_the_name() => _event.Name.Value.ShouldEqual("Ada");
}
