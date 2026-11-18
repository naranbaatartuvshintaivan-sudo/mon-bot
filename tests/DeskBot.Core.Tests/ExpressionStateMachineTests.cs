using DeskBot.Core.Expressions;

namespace DeskBot.Core.Tests;

public class ExpressionStateMachineTests
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 18, 9, 0, 0, TimeSpan.FromHours(8));

    [Fact]
    public void Defaults_to_idle()
    {
        var sm = new ExpressionStateMachine();
        Assert.Equal(Expression.Idle, sm.Current);
    }

    [Fact]
    public void Higher_priority_wins_immediately()
    {
        var sm = new ExpressionStateMachine();
        sm.Set(ExpressionSource.Music, Expression.Music, T0);
        sm.Set(ExpressionSource.Error, Expression.Error, T0);
        Assert.Equal(Expression.Error, sm.Current);
    }

    [Fact]
    public void Lower_priority_does_not_override()
    {
        var sm = new ExpressionStateMachine();
        sm.Set(ExpressionSource.Reminder, Expression.Reminder, T0);
        sm.Set(ExpressionSource.Music, Expression.Music, T0);
        Assert.Equal(Expression.Reminder, sm.Current);
    }

    [Fact]
    public void Timed_layer_expires_on_tick_and_falls_back()
    {
        var sm = new ExpressionStateMachine();
        sm.Set(ExpressionSource.Music, Expression.Music, T0);
        sm.Set(ExpressionSource.UserClick, Expression.Surprised, T0, TimeSpan.FromMilliseconds(400));
        Assert.Equal(Expression.Surprised, sm.Current);

        sm.Tick(T0.AddMilliseconds(500));
        Assert.Equal(Expression.Music, sm.Current);
    }

    [Fact]
    public void Downgrade_is_held_for_min_hold_to_prevent_flicker()
    {
        var sm = new ExpressionStateMachine { MinHold = TimeSpan.FromMilliseconds(300) };
        sm.Set(ExpressionSource.UserClick, Expression.Surprised, T0);
        sm.Clear(ExpressionSource.UserClick, T0.AddMilliseconds(50));
        Assert.Equal(Expression.Surprised, sm.Current); // хараахан бууж болохгүй

        sm.Tick(T0.AddMilliseconds(400));
        Assert.Equal(Expression.Idle, sm.Current);
    }

    [Fact]
    public void Angry_can_never_be_base_mood()
    {
        var sm = new ExpressionStateMachine();
        sm.SetBaseMood(Expression.Angry, T0);
        Assert.Equal(Expression.Idle, sm.Current);

        sm.SetBaseMood(Expression.Happy, T0);
        Assert.Equal(Expression.Happy, sm.Current);
    }

    [Fact]
    public void Changed_event_fires_only_on_real_change()
    {
        var sm = new ExpressionStateMachine();
        var count = 0;
        sm.Changed += _ => count++;
        sm.Set(ExpressionSource.Music, Expression.Music, T0);
        sm.Set(ExpressionSource.Music, Expression.Music, T0);
        Assert.Equal(1, count);
    }

    [Fact]
    public void Base_mood_returns_after_all_layers_cleared()
    {
        var sm = new ExpressionStateMachine { MinHold = TimeSpan.Zero };
        sm.SetBaseMood(Expression.Happy, T0);
        sm.Set(ExpressionSource.Error, Expression.Error, T0);
        sm.Clear(ExpressionSource.Error, T0.AddSeconds(1));
        Assert.Equal(Expression.Happy, sm.Current);
    }
}

public class EyeMathTests
{
    [Fact]
    public void Look_vector_is_bounded()
    {
        var (x, y) = EyeMath.LookVector(5000, 5000, 400);
        Assert.InRange(Math.Sqrt(x * x + y * y), 0.99, 1.0001);
    }

    [Fact]
    public void Look_vector_zero_at_center()
    {
        Assert.Equal((0d, 0d), EyeMath.LookVector(0, 0, 400));
    }

    [Fact]
    public void Smooth_factor_is_frame_rate_independent()
    {
        // 2 × 8ms алхам == 1 × 16ms алхам
        var a = EyeMath.SmoothFactor(0.008, 10);
        var two = 1 - (1 - a) * (1 - a);
        Assert.Equal(EyeMath.SmoothFactor(0.016, 10), two, 6);
    }

    [Fact]
    public void Blink_closes_in_the_middle()
    {
        Assert.Equal(1, EyeMath.BlinkOpenness(0));
        Assert.True(EyeMath.BlinkOpenness(0.5) < 0.1);
    }

    [Fact]
    public void Face_lerp_endpoints()
    {
        var a = FaceLibrary.For(Expression.Idle);
        var b = FaceLibrary.For(Expression.Angry);
        Assert.Equal(a, FaceParameters.Lerp(a, b, 0));
        Assert.Equal(b, FaceParameters.Lerp(a, b, 1));
    }

    [Fact]
    public void Every_expression_has_parameters()
    {
        foreach (var e in Enum.GetValues<Expression>())
            Assert.True(FaceLibrary.For(e).EyeWidth > 0);
    }
}
